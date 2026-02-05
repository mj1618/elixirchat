# Task: Scheduled Messages

## Description
Allow users to schedule messages to be sent at a future time. This is useful for timezone differences, reminders, delayed announcements, or when you want to compose a message now but have it delivered later. Users can view, edit, and cancel their scheduled messages before they're sent.

## Requirements
- Users can schedule a message when composing by selecting a future date/time
- Scheduled messages are stored and sent automatically at the scheduled time
- Users can view a list of their pending scheduled messages
- Users can edit or cancel scheduled messages before they're sent
- Scheduled messages work for both direct messages and group chats
- Shows a clear indicator when a scheduled message is pending
- Minimum scheduling time is 1 minute in the future
- Scheduled messages support all regular message features (attachments, replies, etc.)

## Implementation Steps

1. **Create ScheduledMessage schema and migration** (`lib/elixirchat/chat/scheduled_message.ex`):
   - Fields: `id`, `content`, `conversation_id`, `sender_id`, `scheduled_for`, `sent_at`, `cancelled_at`
   - Optional: `reply_to_id` for replies
   - Belongs to Conversation, User, and optionally Message (reply_to)
   - Create migration file

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration create_scheduled_messages
   ```
   ```elixir
   create table(:scheduled_messages) do
     add :content, :text, null: false
     add :scheduled_for, :utc_datetime, null: false
     add :sent_at, :utc_datetime
     add :cancelled_at, :utc_datetime
     add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
     add :sender_id, references(:users, on_delete: :delete_all), null: false
     add :reply_to_id, references(:messages, on_delete: :nilify_all)
     timestamps()
   end

   create index(:scheduled_messages, [:sender_id])
   create index(:scheduled_messages, [:scheduled_for])
   create index(:scheduled_messages, [:conversation_id])
   ```

3. **Add scheduled message functions to Chat context** (`lib/elixirchat/chat.ex`):
   - `schedule_message/4` - Schedule a new message (conversation_id, sender_id, content, scheduled_for, opts)
   - `get_scheduled_message!/1` - Get a scheduled message by ID
   - `list_user_scheduled_messages/1` - Get all pending scheduled messages for a user
   - `list_conversation_scheduled_messages/2` - Get pending scheduled messages in a conversation for a user
   - `update_scheduled_message/3` - Update content or time (only if not sent)
   - `cancel_scheduled_message/2` - Cancel a scheduled message (soft delete via cancelled_at)
   - `send_scheduled_message/1` - Actually send the message (called by scheduler)
   - `get_due_scheduled_messages/0` - Get messages due to be sent

4. **Create ScheduledMessageWorker** (`lib/elixirchat/chat/scheduled_message_worker.ex`):
   - GenServer that runs every minute to check for due messages
   - Sends messages that are past their scheduled_for time
   - Updates sent_at after successful send
   - Add to application supervision tree

5. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add schedule button next to send button
   - Add datetime picker modal for selecting schedule time
   - Add `handle_event("schedule_message", ...)` to schedule instead of send
   - Show indicator when user has pending scheduled messages in conversation

6. **Create ScheduledMessagesLive** (`lib/elixirchat_web/live/scheduled_messages_live.ex`):
   - New LiveView page to display all scheduled messages for a user
   - Group by conversation
   - Show content preview, target conversation, scheduled time
   - Allow editing content and time
   - Allow cancelling scheduled messages
   - Click to navigate to conversation

7. **Update Router** (`lib/elixirchat_web/router.ex`):
   - Add route for `/scheduled` -> ScheduledMessagesLive

8. **Update Navigation**:
   - Add "Scheduled" link in sidebar/navigation with badge count

## Technical Details

### ScheduledMessage Schema
```elixir
defmodule Elixirchat.Chat.ScheduledMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Conversation, Message}
  alias Elixirchat.Accounts.User

  schema "scheduled_messages" do
    field :content, :string
    field :scheduled_for, :utc_datetime
    field :sent_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    belongs_to :conversation, Conversation
    belongs_to :sender, User
    belongs_to :reply_to, Message

    timestamps()
  end

  def changeset(scheduled_message, attrs) do
    scheduled_message
    |> cast(attrs, [:content, :scheduled_for, :sent_at, :cancelled_at, :conversation_id, :sender_id, :reply_to_id])
    |> validate_required([:content, :scheduled_for, :conversation_id, :sender_id])
    |> validate_length(:content, min: 1, max: 10000)
    |> validate_scheduled_for_future()
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:reply_to_id)
  end

  defp validate_scheduled_for_future(changeset) do
    scheduled_for = get_field(changeset, :scheduled_for)
    
    if scheduled_for && DateTime.compare(scheduled_for, DateTime.utc_now()) != :gt do
      add_error(changeset, :scheduled_for, "must be in the future")
    else
      changeset
    end
  end
end
```

### Chat Context Functions
```elixir
def schedule_message(conversation_id, sender_id, content, scheduled_for, opts \\ []) do
  # Verify sender is member of conversation
  if member?(conversation_id, sender_id) do
    reply_to_id = Keyword.get(opts, :reply_to_id)
    
    attrs = %{
      content: content,
      scheduled_for: scheduled_for,
      conversation_id: conversation_id,
      sender_id: sender_id,
      reply_to_id: reply_to_id
    }

    %ScheduledMessage{}
    |> ScheduledMessage.changeset(attrs)
    |> Repo.insert()
  else
    {:error, :not_a_member}
  end
end

def list_user_scheduled_messages(user_id) do
  from(s in ScheduledMessage,
    where: s.sender_id == ^user_id,
    where: is_nil(s.sent_at) and is_nil(s.cancelled_at),
    order_by: [asc: s.scheduled_for],
    preload: [:conversation]
  )
  |> Repo.all()
end

def cancel_scheduled_message(scheduled_message_id, user_id) do
  case Repo.get(ScheduledMessage, scheduled_message_id) do
    nil -> 
      {:error, :not_found}
    
    %{sender_id: ^user_id, sent_at: nil, cancelled_at: nil} = msg ->
      msg
      |> Ecto.Changeset.change(%{cancelled_at: DateTime.utc_now()})
      |> Repo.update()
    
    %{sent_at: sent_at} when not is_nil(sent_at) ->
      {:error, :already_sent}
    
    %{cancelled_at: cancelled_at} when not is_nil(cancelled_at) ->
      {:error, :already_cancelled}
    
    _ ->
      {:error, :not_owner}
  end
end

def get_due_scheduled_messages do
  now = DateTime.utc_now()
  
  from(s in ScheduledMessage,
    where: s.scheduled_for <= ^now,
    where: is_nil(s.sent_at) and is_nil(s.cancelled_at),
    preload: [:sender]
  )
  |> Repo.all()
end

def send_scheduled_message(scheduled_message) do
  # Send the actual message
  opts = if scheduled_message.reply_to_id, do: [reply_to_id: scheduled_message.reply_to_id], else: []
  
  case send_message(scheduled_message.conversation_id, scheduled_message.sender_id, scheduled_message.content, opts) do
    {:ok, message} ->
      # Mark as sent
      scheduled_message
      |> Ecto.Changeset.change(%{sent_at: DateTime.utc_now()})
      |> Repo.update()
      
      {:ok, message}
    
    error ->
      error
  end
end
```

### ScheduledMessageWorker
```elixir
defmodule Elixirchat.Chat.ScheduledMessageWorker do
  use GenServer
  require Logger

  alias Elixirchat.Chat

  @check_interval :timer.seconds(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_scheduled, state) do
    process_due_messages()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_scheduled, @check_interval)
  end

  defp process_due_messages do
    Chat.get_due_scheduled_messages()
    |> Enum.each(fn scheduled_msg ->
      case Chat.send_scheduled_message(scheduled_msg) do
        {:ok, _message} ->
          Logger.info("Sent scheduled message #{scheduled_msg.id}")
        
        {:error, reason} ->
          Logger.error("Failed to send scheduled message #{scheduled_msg.id}: #{inspect(reason)}")
      end
    end)
  end
end
```

### UI Components

#### Schedule Button (next to send)
```heex
<div class="flex items-center gap-1">
  <button type="submit" class="btn btn-primary">Send</button>
  <div class="dropdown dropdown-top dropdown-end">
    <button type="button" tabindex="0" class="btn btn-ghost btn-sm">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
      </svg>
    </button>
    <div tabindex="0" class="dropdown-content z-[1] p-4 shadow bg-base-100 rounded-box w-72">
      <h3 class="font-semibold mb-2">Schedule Message</h3>
      <input type="datetime-local" name="scheduled_for" class="input input-bordered w-full mb-2" min={min_datetime()} />
      <button type="button" phx-click="schedule_message" class="btn btn-sm btn-primary w-full">Schedule</button>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] Schedule button visible next to send button
- [ ] Datetime picker allows selecting future date/time
- [ ] Scheduled message is created with correct scheduled_for time
- [ ] Scheduled messages page shows all pending scheduled messages
- [ ] Can edit scheduled message content before it's sent
- [ ] Can change scheduled time before it's sent
- [ ] Can cancel scheduled message before it's sent
- [ ] Message is automatically sent at scheduled time
- [ ] Sent scheduled messages appear in conversation like normal messages
- [ ] Cancelled messages don't get sent
- [ ] Cannot schedule message in conversation user isn't member of
- [ ] Works for both direct messages and group chats
- [ ] Badge shows count of pending scheduled messages in nav
- [ ] Scheduled messages support reply_to

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Schedule a message for 1 minute in the future, verify it gets sent
- Schedule multiple messages, verify they send in correct order
- Edit a scheduled message's content, verify change persists
- Change scheduled time, verify it sends at new time
- Cancel a scheduled message, verify it's never sent
- Try to schedule for past time, verify error
- Try to edit an already-sent message, verify error
- Schedule in a group chat, verify it sends to group
- Schedule with a reply, verify reply_to is preserved

## Edge Cases to Handle
- User leaves conversation before scheduled time (cancel or send anyway?)
- Conversation is deleted before scheduled time (cascade delete)
- User tries to schedule with empty content
- Server restart - worker should pick up pending messages
- User's timezone vs UTC handling in datetime picker
- Very long scheduling delay (weeks/months in future)
- Multiple messages scheduled for exact same time

---

## Completion Notes (Agent d12ce640)

**Completed:** February 5, 2026

### What was implemented:
1. **ScheduledMessage schema and migration** - Created `lib/elixirchat/chat/scheduled_message.ex` with fields for content, scheduled_for, sent_at, cancelled_at, and relationships to conversation, sender, and reply_to
2. **Migration** - Created `priv/repo/migrations/20260205054648_create_scheduled_messages.exs` with proper indexes
3. **Chat context functions** - Added to `lib/elixirchat/chat.ex`:
   - `schedule_message/5` - Schedule a new message
   - `get_scheduled_message!/1` and `get_scheduled_message/1` - Retrieve scheduled messages
   - `list_user_scheduled_messages/1` - List all pending scheduled messages for a user
   - `list_conversation_scheduled_messages/2` - List pending messages for a conversation
   - `get_scheduled_message_count/1` - Get count of pending scheduled messages
   - `update_scheduled_message/3` - Update content and/or scheduled time
   - `cancel_scheduled_message/2` - Soft cancel a scheduled message
   - `get_due_scheduled_messages/0` - Get messages ready to be sent
   - `send_scheduled_message/1` - Actually send a scheduled message
4. **ScheduledMessageWorker GenServer** - Created `lib/elixirchat/chat/scheduled_message_worker.ex` that runs every 30 seconds checking for due messages
5. **Application supervision** - Added worker to `lib/elixirchat/application.ex`
6. **ChatLive updates** - Added schedule button next to send button, schedule modal with datetime picker, and event handlers
7. **ScheduledMessagesLive** - Created `lib/elixirchat_web/live/scheduled_messages_live.ex` for viewing/editing/cancelling scheduled messages
8. **Router** - Added `/scheduled` route
9. **Navigation** - Added scheduled messages icon with badge in chat list

### Additional fixes:
- Fixed missing `get_member_role/2` function that was referenced but not defined
- Added `GroupInvite` to the alias list in chat.ex

### Testing:
- Verified the app compiles successfully
- Verified the UI shows schedule button in chat view
- Verified the scheduled messages navigation icon appears in chat list

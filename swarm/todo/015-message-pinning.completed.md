# Task: Message Pinning

## Description
Add the ability to pin important messages in conversations. Pinned messages appear at the top of the chat (or in a dedicated pinned section) so they're always visible and easy to find. This is useful for highlighting important information, rules, announcements, or decisions in both direct and group chats.

## Requirements
- Any conversation member can pin a message
- Pinned messages appear in a dedicated section at the top of the chat
- Users can click on a pinned message to jump to it in the chat history
- Users can unpin messages (only the pinner or message author)
- Maximum of 5 pinned messages per conversation
- Real-time: pin/unpin updates appear for all conversation members via PubSub
- Deleted messages are automatically unpinned
- Shows who pinned the message and when

## Implementation Steps

1. **Create PinnedMessage schema and migration** (`lib/elixirchat/chat/pinned_message.ex`):
   - Fields: `id`, `message_id`, `conversation_id`, `pinned_by_id` (user who pinned), `pinned_at`
   - Belongs to Message, Conversation, and User
   - Unique constraint on `[:message_id]` (message can only be pinned once)
   - Index on conversation_id

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration create_pinned_messages
   ```
   ```elixir
   create table(:pinned_messages) do
     add :pinned_at, :utc_datetime, null: false
     add :message_id, references(:messages, on_delete: :delete_all), null: false
     add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
     add :pinned_by_id, references(:users, on_delete: :nilify_all)
     timestamps()
   end

   create unique_index(:pinned_messages, [:message_id])
   create index(:pinned_messages, [:conversation_id])
   ```

3. **Add pin functions to Chat context** (`lib/elixirchat/chat.ex`):
   - `pin_message/3` - Pin a message (conversation_id, message_id, user_id)
   - `unpin_message/2` - Unpin a message (message_id, user_id)
   - `list_pinned_messages/1` - Get all pinned messages for a conversation
   - `is_pinned?/1` - Check if a message is pinned
   - `can_unpin?/3` - Check if user can unpin (is pinner or message author)
   - `broadcast_pin_update/2` - Broadcast pin/unpin changes via PubSub

4. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `pinned_messages` to socket assigns in mount
   - Add `handle_event("pin_message", ...)` to pin a message
   - Add `handle_event("unpin_message", ...)` to unpin a message
   - Add `handle_event("toggle_pinned", ...)` to show/hide pinned section
   - Add `handle_event("jump_to_pinned", ...)` to scroll to pinned message
   - Add `handle_info({:message_pinned, ...}, ...)` for pin broadcasts
   - Add `handle_info({:message_unpinned, ...}, ...)` for unpin broadcasts
   - Add pin button to message hover actions

5. **Update chat UI**:
   - Add pin button (thumbtack icon) in message hover actions
   - Add collapsible pinned messages section at top of chat
   - Show pinned messages with message preview, author, and pinner info
   - Allow clicking pinned message to jump to it in chat
   - Show unpin button next to each pinned message
   - Indicate pinned messages in the main chat (subtle pin icon)

## Technical Details

### PinnedMessage Schema
```elixir
defmodule Elixirchat.Chat.PinnedMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pinned_messages" do
    field :pinned_at, :utc_datetime
    belongs_to :message, Elixirchat.Chat.Message
    belongs_to :conversation, Elixirchat.Chat.Conversation
    belongs_to :pinned_by, Elixirchat.Accounts.User

    timestamps()
  end

  @max_pins_per_conversation 5

  def changeset(pinned_message, attrs) do
    pinned_message
    |> cast(attrs, [:pinned_at, :message_id, :conversation_id, :pinned_by_id])
    |> validate_required([:pinned_at, :message_id, :conversation_id, :pinned_by_id])
    |> unique_constraint(:message_id, message: "message is already pinned")
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:pinned_by_id)
  end

  def max_pins_per_conversation, do: @max_pins_per_conversation
end
```

### Pin/Unpin Functions
```elixir
def pin_message(conversation_id, message_id, user_id) do
  # Check pin limit
  current_pin_count = 
    from(p in PinnedMessage, where: p.conversation_id == ^conversation_id, select: count(p.id))
    |> Repo.one()

  if current_pin_count >= PinnedMessage.max_pins_per_conversation() do
    {:error, :pin_limit_reached}
  else
    # Verify message belongs to conversation
    message = Repo.get!(Message, message_id) |> Repo.preload(:sender)
    
    if message.conversation_id != conversation_id do
      {:error, :invalid_message}
    else
      result =
        %PinnedMessage{}
        |> PinnedMessage.changeset(%{
          message_id: message_id,
          conversation_id: conversation_id,
          pinned_by_id: user_id,
          pinned_at: DateTime.utc_now()
        })
        |> Repo.insert()

      case result do
        {:ok, pinned} ->
          pinned = Repo.preload(pinned, [:message, :pinned_by])
          broadcast_pin_update(conversation_id, {:message_pinned, pinned})
          {:ok, pinned}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end
end

def unpin_message(message_id, user_id) do
  pinned = Repo.get_by(PinnedMessage, message_id: message_id)

  case pinned do
    nil ->
      {:error, :not_pinned}

    pinned ->
      message = Repo.get!(Message, message_id)
      
      # Only pinner or message author can unpin
      if pinned.pinned_by_id == user_id || message.sender_id == user_id do
        {:ok, _} = Repo.delete(pinned)
        broadcast_pin_update(pinned.conversation_id, {:message_unpinned, message_id})
        :ok
      else
        {:error, :not_authorized}
      end
  end
end

def list_pinned_messages(conversation_id) do
  from(p in PinnedMessage,
    where: p.conversation_id == ^conversation_id,
    preload: [message: :sender, pinned_by: []],
    order_by: [desc: p.pinned_at]
  )
  |> Repo.all()
end
```

### PubSub Events
```elixir
# Broadcast pin/unpin updates
{:message_pinned, pinned_message}
{:message_unpinned, message_id}
```

### UI Components

```heex
<%!-- Pinned messages section (collapsible) --%>
<div :if={length(@pinned_messages) > 0} class="bg-base-200 border-b border-base-300">
  <button 
    phx-click="toggle_pinned"
    class="w-full px-4 py-2 flex items-center justify-between hover:bg-base-300"
  >
    <div class="flex items-center gap-2">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
      </svg>
      <span class="text-sm font-medium">{length(@pinned_messages)} Pinned</span>
    </div>
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class={["w-4 h-4 transition-transform", @show_pinned && "rotate-180"]}>
      <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
    </svg>
  </button>
  
  <div :if={@show_pinned} class="px-4 pb-2 space-y-2">
    <div
      :for={pinned <- @pinned_messages}
      class="flex items-start justify-between gap-2 p-2 bg-base-100 rounded hover:bg-base-300 cursor-pointer"
      phx-click="jump_to_pinned"
      phx-value-message-id={pinned.message.id}
    >
      <div class="flex-1 min-w-0">
        <div class="text-xs text-base-content/60">
          <span class="font-medium">{pinned.message.sender.username}</span>
          <span> • Pinned by {pinned.pinned_by.username}</span>
        </div>
        <p class="text-sm truncate">{pinned.message.content}</p>
      </div>
      <button
        :if={can_unpin?(@current_user.id, pinned)}
        phx-click="unpin_message"
        phx-value-message-id={pinned.message.id}
        class="btn btn-ghost btn-xs btn-circle flex-shrink-0"
        title="Unpin"
      >
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  </div>
</div>

<%!-- Pin button in message actions --%>
<button
  :if={is_nil(message.deleted_at)}
  phx-click={if is_message_pinned?(message.id, @pinned_messages), do: "unpin_message", else: "pin_message"}
  phx-value-message-id={message.id}
  class={["btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm", is_message_pinned?(message.id, @pinned_messages) && "text-warning"]}
  title={if is_message_pinned?(message.id, @pinned_messages), do: "Unpin", else: "Pin"}
>
  <svg xmlns="http://www.w3.org/2000/svg" fill={if is_message_pinned?(message.id, @pinned_messages), do: "currentColor", else: "none"} viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
    <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
  </svg>
</button>

<%!-- Pin indicator in message bubble (subtle) --%>
<div :if={is_message_pinned?(message.id, @pinned_messages)} class="absolute -left-5 top-1/2 -translate-y-1/2">
  <svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 24 24" class="w-3 h-3 text-warning">
    <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
  </svg>
</div>
```

## Acceptance Criteria
- [x] Users can pin messages via hover action button
- [x] Pinned messages appear in collapsible section at top
- [x] Shows who pinned the message
- [x] Clicking pinned message jumps to it in chat
- [x] Users can unpin messages (pinner or message author only)
- [x] Maximum 5 pinned messages per conversation
- [x] Error shown when pin limit reached
- [x] Pin/unpin updates appear in real-time for all members
- [x] Deleted messages are automatically unpinned (via DB cascade)
- [x] Pinned messages indicate pinned status in chat
- [x] Works in both direct and group chats
- [x] Pinned messages persist across page refreshes

## Implementation Notes (Added by agent ce7804b1)

Implemented the full message pinning feature:

1. **Created Migration** (`priv/repo/migrations/20260205045509_create_pinned_messages.exs`):
   - Table with pinned_at, message_id, conversation_id, pinned_by_id
   - Unique index on message_id (a message can only be pinned once)
   - Index on conversation_id for efficient lookup
   - Cascade delete on message/conversation deletion

2. **Created PinnedMessage Schema** (`lib/elixirchat/chat/pinned_message.ex`):
   - Belongs to Message, Conversation, and User (pinned_by)
   - Maximum 5 pins per conversation constant

3. **Added Chat Context Functions** (`lib/elixirchat/chat.ex`):
   - `pin_message/3` - Pins a message with validation (limit, ownership, deleted check)
   - `unpin_message/2` - Unpins a message (only pinner or author can unpin)
   - `list_pinned_messages/1` - Lists all pins for a conversation
   - `is_message_pinned?/1` - Checks if a message is pinned
   - `get_pinned_message_ids/1` - Gets pinned IDs as MapSet for fast lookup
   - `broadcast_pin_update/2` - PubSub broadcast for pin/unpin events

4. **Updated ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Added `pinned_messages` and `show_pinned` assigns
   - Added event handlers: pin_message, unpin_message, toggle_pinned, jump_to_pinned
   - Added PubSub handlers: :message_pinned, :message_unpinned
   - Added pinned messages collapsible section UI at top of chat
   - Added pin button in message hover actions
   - Helper functions: `is_message_pinned?/2`, `can_unpin?/2`

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Send several messages in a conversation
- Pin a message and verify it appears in pinned section
- Click the pinned message and verify scroll to original
- Open conversation in another browser as different user
- Verify pinned message appears in real-time
- Try to pin 6 messages (should show error on 6th)
- Unpin a message as the pinner
- Try to unpin as a different user (should fail)
- Unpin as the message author (should succeed)
- Delete a pinned message and verify it's unpinned
- Refresh page and verify pins persist
- Test in both direct and group conversations

## Edge Cases to Handle
- User tries to pin a deleted message (reject)
- User tries to pin more than 5 messages (show error)
- Message is deleted while pinned (auto-unpin via cascade)
- User who pinned leaves the group (keep pin, nullify pinned_by)
- Clicking jump to message when message is no longer visible (scroll to it)
- Very long message content in pinned preview (truncate)
- User tries to pin same message twice (already pinned error)
- Concurrent pin attempts from multiple users (handle gracefully)

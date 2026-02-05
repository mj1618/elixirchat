# Task: Mute Conversations

## Completion Notes

**Completed by agent bf14801e on Feb 5, 2026**

Implementation completed:
1. Created migration `20260205060000_create_muted_conversations.exs` with user_id and conversation_id fields
2. Created `MutedConversation` schema at `lib/elixirchat/chat/muted_conversation.ex`
3. Added mute functions to Chat context: `mute_conversation/2`, `unmute_conversation/2`, `is_muted?/2`, `list_muted_conversation_ids/1`, `toggle_mute/2`
4. Updated ChatLive with:
   - `is_muted` assign loaded on mount
   - Mute/unmute button in chat header with visual feedback
   - `toggle_mute` event handler
   - Notification logic updated to skip notifications for muted conversations
5. Updated ChatListLive with muted conversation indicators

Also fixed a bug in `application.ex` where `ensure_general_conversation()` was being called before the Repo was fully started (moved to supervised Task).

All acceptance criteria should be met. The mute status persists in the database and survives page refreshes.

---

## Description
Allow users to mute notifications from specific conversations. When a conversation is muted, the user will no longer receive browser notifications for new messages in that conversation, but the conversation will still appear in their chat list and show unread indicators. This is useful for users who are part of active group chats but don't want to be constantly notified.

## Requirements
- Users can mute/unmute individual conversations (both direct and group)
- Muted conversations don't trigger browser notifications for new messages
- Muted status persists across sessions (stored in database)
- Visual indicator on muted conversations in chat list (mute icon)
- Mute/unmute button in:
  - Chat header (when viewing the conversation)
  - Conversation list item (dropdown or swipe action on mobile)
- Muted conversations still show unread badges/indicators
- Cannot mute the General group (optional - could allow this)

## Implementation Steps

1. **Create muted_conversations table** (migration):
   - Create join table between users and conversations
   - Fields: user_id, conversation_id, inserted_at
   - Unique constraint on user_id + conversation_id

2. **Create MutedConversation schema** (`lib/elixirchat/chat/muted_conversation.ex`):
   - Define schema with belongs_to for user and conversation
   - Add changeset

3. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Add `mute_conversation/2` - creates muted_conversation record
   - Add `unmute_conversation/2` - deletes muted_conversation record
   - Add `is_muted?/2` - checks if user has muted a conversation
   - Add `list_muted_conversation_ids/1` - returns list of muted conversation IDs for user
   - Update conversation queries to include muted status where needed

4. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `is_muted` assign (boolean)
   - Add mute/unmute button in chat header
   - Handle `"toggle_mute"` event
   - Update notification logic to check muted status before sending

5. **Update ChatListLive** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Load muted conversation IDs on mount
   - Display mute icon for muted conversations
   - Add mute/unmute option to conversation actions

6. **Update notification push event** (in ChatLive):
   - Before pushing "notify" event, check if conversation is muted
   - Skip notification for muted conversations

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.CreateMutedConversations do
  use Ecto.Migration

  def change do
    create table(:muted_conversations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:muted_conversations, [:user_id, :conversation_id])
    create index(:muted_conversations, [:user_id])
  end
end
```

### MutedConversation Schema
```elixir
defmodule Elixirchat.Chat.MutedConversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User
  alias Elixirchat.Chat.Conversation

  schema "muted_conversations" do
    belongs_to :user, User
    belongs_to :conversation, Conversation

    timestamps(updated_at: false)
  end

  def changeset(muted_conversation, attrs) do
    muted_conversation
    |> cast(attrs, [:user_id, :conversation_id])
    |> validate_required([:user_id, :conversation_id])
    |> unique_constraint([:user_id, :conversation_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:conversation_id)
  end
end
```

### Chat Context Functions
```elixir
alias Elixirchat.Chat.MutedConversation

def mute_conversation(conversation_id, user_id) do
  %MutedConversation{}
  |> MutedConversation.changeset(%{conversation_id: conversation_id, user_id: user_id})
  |> Repo.insert(on_conflict: :nothing)
end

def unmute_conversation(conversation_id, user_id) do
  from(m in MutedConversation,
    where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
  )
  |> Repo.delete_all()

  :ok
end

def is_muted?(conversation_id, user_id) do
  from(m in MutedConversation,
    where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
  )
  |> Repo.exists?()
end

def list_muted_conversation_ids(user_id) do
  from(m in MutedConversation,
    where: m.user_id == ^user_id,
    select: m.conversation_id
  )
  |> Repo.all()
end

def toggle_mute(conversation_id, user_id) do
  if is_muted?(conversation_id, user_id) do
    unmute_conversation(conversation_id, user_id)
    {:ok, :unmuted}
  else
    mute_conversation(conversation_id, user_id)
    {:ok, :muted}
  end
end
```

### ChatLive Updates
```elixir
# In mount - add is_muted assign
is_muted = Chat.is_muted?(conversation_id, current_user.id)
# ... add to assigns
|> assign(is_muted: is_muted)

# Event handler
def handle_event("toggle_mute", _, socket) do
  conversation_id = socket.assigns.conversation.id
  user_id = socket.assigns.current_user.id

  case Chat.toggle_mute(conversation_id, user_id) do
    {:ok, :muted} ->
      {:noreply,
       socket
       |> assign(is_muted: true)
       |> put_flash(:info, "Conversation muted")}

    {:ok, :unmuted} ->
      {:noreply,
       socket
       |> assign(is_muted: false)
       |> put_flash(:info, "Conversation unmuted")}
  end
end

# Update notification sending (in handle_info for :new_message)
# Before pushing notify event, add check:
socket =
  if message.sender_id != socket.assigns.current_user.id && !socket.assigns.is_muted do
    push_event(socket, "notify", %{...})
  else
    socket
  end
```

### UI - Mute Button in Chat Header
```heex
<%!-- Add to header buttons, next to theme toggle --%>
<button
  phx-click="toggle_mute"
  class={["btn btn-ghost btn-sm", @is_muted && "text-warning"]}
  title={if @is_muted, do: "Unmute notifications", else: "Mute notifications"}
>
  <%= if @is_muted do %>
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M17.25 9.75 19.5 12m0 0 2.25 2.25M19.5 12l2.25-2.25M19.5 12l-2.25 2.25m-10.5-6 4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z" />
    </svg>
  <% else %>
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19.114 5.636a9 9 0 0 1 0 12.728M16.463 8.288a5.25 5.25 0 0 1 0 7.424M6.75 8.25l4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53L6.75 15.75H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z" />
    </svg>
  <% end %>
</button>
```

### UI - Mute Icon in Chat List
```heex
<%!-- In conversation list item, add mute indicator --%>
<div class="flex items-center gap-1">
  <span :if={conversation.id in @muted_conversation_ids} class="text-warning" title="Muted">
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
      <path stroke-linecap="round" stroke-linejoin="round" d="M17.25 9.75 19.5 12m0 0 2.25 2.25M19.5 12l2.25-2.25M19.5 12l-2.25 2.25m-10.5-6 4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z" />
    </svg>
  </span>
  <span class="truncate">{get_conversation_name(conversation, @current_user.id)}</span>
</div>
```

## Acceptance Criteria
- [ ] Users can mute a conversation from the chat header
- [ ] Muted conversations don't trigger browser notifications
- [ ] Mute icon appears on muted conversations in chat list
- [ ] Muted status persists after page refresh / re-login
- [ ] Users can unmute a conversation
- [ ] Unmuting re-enables browser notifications
- [ ] Muted conversations still show unread message indicators
- [ ] Works for both direct messages and group chats

## Dependencies
- Task 018: Browser Notifications (completed)
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Mute a conversation and verify no browser notification appears for new messages
- Unmute and verify notifications work again
- Verify mute icon appears in conversation list
- Verify mute status persists after page reload
- Test muting both direct messages and group chats
- Log in as a different user and verify their mute settings are independent
- Verify muted conversations still show unread count/badge

## Edge Cases to Handle
- User mutes a conversation they're currently viewing
- User is removed from a muted group (cleanup muted record?)
- Conversation is deleted (cascade delete should handle)
- User mutes while offline (should work on reconnect)
- Multiple browser tabs (mute state should sync)

## Future Enhancements (not in this task)
- Mute for a specific duration (1 hour, 1 day, 1 week, forever)
- Mute all group conversations at once
- Do Not Disturb mode (mute all conversations)
- Custom notification sounds per conversation
- Notification settings page with list of muted conversations

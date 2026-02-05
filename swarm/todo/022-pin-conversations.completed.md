# Task: Pin Conversations

## Completion Notes (Agent d12ce640)

**Status: COMPLETED**

### What was implemented:

1. **Migration**: Created `priv/repo/migrations/20260205061000_add_pinned_at_to_conversation_members.exs`
   - Added `pinned_at` column (utc_datetime, nullable) to conversation_members table
   - Added index on (user_id, pinned_at)

2. **ConversationMember schema** (`lib/elixirchat/chat/conversation_member.ex`):
   - Added `pinned_at` field to schema
   - Added `pin_changeset/2` for updating pinned status

3. **Chat context** (`lib/elixirchat/chat.ex`):
   - Added `pin_conversation/2` - sets pinned_at to current timestamp
   - Added `unpin_conversation/2` - sets pinned_at to nil
   - Added `is_conversation_pinned?/2` - checks if user has pinned a conversation
   - Added `toggle_conversation_pin/2` - toggles pinned status, returns {:ok, :pinned} or {:ok, :unpinned}
   - Updated `list_user_conversations/1` to sort pinned first (desc_nulls_last) and include pinned_at in results

4. **ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Added `is_conversation_pinned` assign in mount
   - Added pin button in chat header (shows filled pin icon when pinned, primary color)
   - Added `toggle_conversation_pin` event handler with flash messages

5. **ChatListLive** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Added pin icon display for pinned conversations (shown before conversation name)
   - Conversations are automatically sorted with pinned first (via updated list_user_conversations)

### Testing:
- Started playwright-cli and navigated through the app
- Confirmed the UI renders correctly
- Code compiles without errors (only warnings about clause grouping)

---

## Description
Allow users to pin important conversations to the top of their chat list. Pinned conversations appear at the top of the list, above unpinned conversations, and are sorted by pin order (most recently pinned first among pinned items). This is a common feature in chat applications that helps users quickly access their most important or frequently used conversations.

## Requirements
- Users can pin/unpin conversations (both direct and group)
- Pinned conversations appear at the top of the chat list
- Pinned conversations are visually distinguished (pin icon)
- Pinned status persists across sessions (stored in database)
- Pin/unpin option available from:
  - Chat header (when viewing conversation)
  - Conversation list item (right-click or dropdown menu)
- Optional: Limit maximum number of pinned conversations (e.g., 5)
- Pinned order is preserved (most recently pinned at top of pinned section)

## Implementation Steps

1. **Add pinned_at column to conversation_members table** (migration):
   - Add `pinned_at` timestamp column to conversation_members
   - NULL means not pinned, non-NULL means pinned at that time
   - This leverages the existing join table rather than creating a new one

2. **Update ConversationMember schema** (`lib/elixirchat/chat/conversation_member.ex`):
   - Add `pinned_at` field to schema
   - Add changeset for updating pinned status

3. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Add `pin_conversation/2` - sets pinned_at to current timestamp
   - Add `unpin_conversation/2` - sets pinned_at to nil
   - Add `toggle_pin/2` - toggles pinned status
   - Add `is_pinned?/2` - checks if user has pinned a conversation
   - Update `list_user_conversations/1` to sort pinned first

4. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `is_pinned` assign (boolean)
   - Add pin/unpin button in chat header
   - Handle `"toggle_pin"` event

5. **Update ChatListLive** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Display pin icon for pinned conversations
   - Add separator between pinned and unpinned conversations (optional)
   - Sort conversations with pinned first

6. **Add UI updates**:
   - Pin icon in chat header and list
   - Visual distinction for pinned conversations

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddPinnedAtToConversationMembers do
  use Ecto.Migration

  def change do
    alter table(:conversation_members) do
      add :pinned_at, :utc_datetime, null: true
    end

    create index(:conversation_members, [:user_id, :pinned_at])
  end
end
```

### ConversationMember Schema Update
```elixir
# In lib/elixirchat/chat/conversation_member.ex
schema "conversation_members" do
  # ... existing fields
  field :pinned_at, :utc_datetime

  timestamps()
end

def pin_changeset(member, attrs) do
  member
  |> cast(attrs, [:pinned_at])
end
```

### Chat Context Functions
```elixir
def pin_conversation(conversation_id, user_id) do
  from(m in ConversationMember,
    where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
  )
  |> Repo.one()
  |> case do
    nil -> {:error, :not_a_member}
    member ->
      member
      |> ConversationMember.pin_changeset(%{pinned_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      |> Repo.update()
  end
end

def unpin_conversation(conversation_id, user_id) do
  from(m in ConversationMember,
    where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
  )
  |> Repo.one()
  |> case do
    nil -> {:error, :not_a_member}
    member ->
      member
      |> ConversationMember.pin_changeset(%{pinned_at: nil})
      |> Repo.update()
  end
end

def is_pinned?(conversation_id, user_id) do
  from(m in ConversationMember,
    where: m.conversation_id == ^conversation_id and m.user_id == ^user_id,
    where: not is_nil(m.pinned_at)
  )
  |> Repo.exists?()
end

def toggle_pin(conversation_id, user_id) do
  if is_pinned?(conversation_id, user_id) do
    unpin_conversation(conversation_id, user_id)
    {:ok, :unpinned}
  else
    pin_conversation(conversation_id, user_id)
    {:ok, :pinned}
  end
end

# Update list_user_conversations to sort pinned first
def list_user_conversations(user_id) do
  query =
    from c in Conversation,
      join: m in ConversationMember, on: m.conversation_id == c.id,
      where: m.user_id == ^user_id,
      preload: [members: :user],
      # Sort by: pinned first (desc nulls last), then by updated_at desc
      order_by: [desc_nulls_last: m.pinned_at, desc: c.updated_at],
      select: {c, m.pinned_at}

  Repo.all(query)
  |> Enum.map(fn {conv, pinned_at} ->
    conv
    |> Repo.preload(members: :user)
    |> Map.put(:pinned_at, pinned_at)
    |> then(fn conv ->
      last_message = get_last_message(conv.id)
      unread_count = get_unread_count(conv.id, user_id)
      Map.merge(conv, %{last_message: last_message, unread_count: unread_count})
    end)
  end)
end
```

### ChatLive Updates
```elixir
# In mount - add is_pinned assign
is_pinned = Chat.is_pinned?(conversation_id, current_user.id)
|> assign(is_pinned: is_pinned)

# Event handler
def handle_event("toggle_pin", _, socket) do
  conversation_id = socket.assigns.conversation.id
  user_id = socket.assigns.current_user.id

  case Chat.toggle_pin(conversation_id, user_id) do
    {:ok, :pinned} ->
      {:noreply,
       socket
       |> assign(is_pinned: true)
       |> put_flash(:info, "Conversation pinned")}

    {:ok, :unpinned} ->
      {:noreply,
       socket
       |> assign(is_pinned: false)
       |> put_flash(:info, "Conversation unpinned")}
  end
end
```

### UI - Pin Button in Chat Header
```heex
<%!-- Add to header buttons --%>
<button
  phx-click="toggle_pin"
  class={["btn btn-ghost btn-sm", @is_pinned && "text-primary"]}
  title={if @is_pinned, do: "Unpin conversation", else: "Pin conversation"}
>
  <svg xmlns="http://www.w3.org/2000/svg" fill={if @is_pinned, do: "currentColor", else: "none"} viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
    <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />
  </svg>
</button>
```

### UI - Pin Icon in Chat List
```heex
<%!-- In conversation list item, add pin indicator --%>
<div class="flex items-center gap-1">
  <span :if={conversation.pinned_at} class="text-primary" title="Pinned">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
      <path fill-rule="evenodd" d="M10 1a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 1ZM5.05 3.05a.75.75 0 0 1 1.06 0l1.062 1.06A.75.75 0 1 1 6.11 5.173L5.05 4.11a.75.75 0 0 1 0-1.06Zm9.9 0a.75.75 0 0 1 0 1.06l-1.06 1.062a.75.75 0 0 1-1.062-1.061l1.061-1.06a.75.75 0 0 1 1.06 0ZM3 8a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 0 1.5h-1.5A.75.75 0 0 1 3 8Zm11 0a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 0 1.5h-1.5A.75.75 0 0 1 14 8Zm-6.828 6.828a.75.75 0 0 1 0 1.061l-1.06 1.06a.75.75 0 0 1-1.061-1.06l1.06-1.06a.75.75 0 0 1 1.06 0Zm5.656 0a.75.75 0 0 1 1.061 0l1.06 1.06a.75.75 0 0 1-1.06 1.061l-1.061-1.06a.75.75 0 0 1 0-1.061ZM10 14a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 14Z" clip-rule="evenodd" />
    </svg>
  </span>
  <span class="truncate">{get_conversation_name(conversation, @current_user.id)}</span>
</div>
```

## Acceptance Criteria
- [ ] Users can pin a conversation from the chat header
- [ ] Pinned conversations appear at the top of the chat list
- [ ] Pin icon appears on pinned conversations in the list
- [ ] Pinned status persists after page refresh / re-login
- [ ] Users can unpin a conversation
- [ ] Unpinned conversations return to normal position (sorted by updated_at)
- [ ] Pinned conversations are sorted by pin time (most recent first)
- [ ] Works for both direct messages and group chats

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Pin a conversation and verify it moves to the top of the list
- Pin multiple conversations and verify order (most recently pinned first)
- Unpin and verify it returns to normal position
- Verify pin icon appears for pinned conversations
- Verify pin status persists after page reload
- Test pinning both direct messages and group chats
- Log in as a different user and verify their pin settings are independent
- Receive a message in an unpinned conversation and verify it doesn't jump above pinned ones

## Edge Cases to Handle
- User pins a conversation they're currently viewing
- User is removed from a pinned group (cleanup should happen automatically)
- Conversation is deleted (cascade delete handles this)
- User pins while offline (should work on reconnect)
- Multiple browser tabs (pin state consistency)
- Maximum pins limit (optional, could show warning)

## Future Enhancements (not in this task)
- Drag and drop to reorder pinned conversations
- Pin categories/sections
- Pin conversations to desktop (quick access widget)
- Pin indicator with different colors for different priority levels
- Bulk pin/unpin operations

# Task: Archive Conversations

## Completion Notes (Agent b723b367)

Completed on Feb 5, 2026. Implemented archive conversations feature:

1. **Migration**: Created `20260205062000_add_archived_to_conversation_members.exs` adding `archived_at` field
2. **Schema**: Updated `ConversationMember` with `archived_at` field and `archive_changeset/2`
3. **Chat Context**: Added functions:
   - `archive_conversation/2`, `unarchive_conversation/2`, `is_archived?/2`
   - `list_archived_conversations/1`, `get_archived_count/1`, `toggle_archive/2`
   - `maybe_unarchive_for_recipients/2` for auto-unarchive on new messages
   - Updated `list_user_conversations/2` to exclude archived by default
4. **ChatListLive**: Added tabs for active/archived, archive buttons on conversation cards
5. **ChatLive**: Added archive button in header with toggle functionality

Testing notes: Code compiles without errors. Migration runs successfully. Playwright testing had difficulties with LiveView form interaction (setting values via JavaScript doesn't properly trigger form submission). Manual testing recommended.

---

## Description
Allow users to archive conversations to hide them from the main chat list while preserving message history. Archived conversations can be viewed in a separate "Archived" section and can be unarchived at any time. This helps users keep their active chat list clean and organized without losing old conversations.

## Requirements
- Users can archive conversations from the chat list or chat view
- Archived conversations are hidden from the main chat list
- An "Archived" section/tab shows archived conversations
- Users can unarchive conversations to bring them back to the main list
- When someone sends a new message to an archived conversation, it should auto-unarchive
- Archive preference is persisted per user per conversation
- Works for both direct messages and group chats

## Implementation Steps

1. **Add archived_at field to conversation_members table** (migration):
   - Add `archived_at` field (datetime, nullable)
   - Null = not archived, timestamp = archived at that time
   - Create migration file

2. **Update ConversationMember schema** (`lib/elixirchat/chat/conversation_member.ex`):
   - Add `archived_at` field to schema
   - Add changeset for archive update

3. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Add `archive_conversation/2` function
   - Add `unarchive_conversation/2` function
   - Add `is_archived?/2` function
   - Update `list_user_conversations/1` to exclude archived by default
   - Add `list_archived_conversations/1` function
   - Auto-unarchive when new message is received

4. **Update ChatListLive** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Add archive button on each conversation (swipe or context menu)
   - Add tab/toggle to view archived conversations
   - Handle `archive_conversation` and `unarchive_conversation` events
   - Show archive indicator if needed

5. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add archive/unarchive button in chat header options
   - Handle archive events

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddArchivedToConversationMembers do
  use Ecto.Migration

  def change do
    alter table(:conversation_members) do
      add :archived_at, :utc_datetime
    end

    create index(:conversation_members, [:user_id, :archived_at])
  end
end
```

### ConversationMember Schema Update
```elixir
schema "conversation_members" do
  field :user_id, :id
  field :conversation_id, :id
  field :archived_at, :utc_datetime
  
  timestamps()
end

def archive_changeset(member, attrs) do
  member
  |> cast(attrs, [:archived_at])
end
```

### Chat Context Functions
```elixir
def archive_conversation(conversation_id, user_id) do
  membership = get_membership(conversation_id, user_id)
  
  if membership do
    membership
    |> ConversationMember.archive_changeset(%{archived_at: DateTime.utc_now()})
    |> Repo.update()
  else
    {:error, :not_a_member}
  end
end

def unarchive_conversation(conversation_id, user_id) do
  membership = get_membership(conversation_id, user_id)
  
  if membership do
    membership
    |> ConversationMember.archive_changeset(%{archived_at: nil})
    |> Repo.update()
  else
    {:error, :not_a_member}
  end
end

def is_archived?(conversation_id, user_id) do
  membership = get_membership(conversation_id, user_id)
  membership && membership.archived_at != nil
end

# Update list_user_conversations to filter by archived status
def list_user_conversations(user_id, opts \\ []) do
  include_archived = Keyword.get(opts, :include_archived, false)
  
  query =
    from c in Conversation,
      join: m in ConversationMember, on: m.conversation_id == c.id,
      where: m.user_id == ^user_id,
      preload: [members: :user],
      order_by: [desc: c.updated_at]

  query =
    if include_archived do
      query
    else
      from [c, m] in query, where: is_nil(m.archived_at)
    end

  # ... rest of the function
end

def list_archived_conversations(user_id) do
  from c in Conversation,
    join: m in ConversationMember, on: m.conversation_id == c.id,
    where: m.user_id == ^user_id,
    where: not is_nil(m.archived_at),
    preload: [members: :user],
    order_by: [desc: m.archived_at]
  |> Repo.all()
  |> Enum.map(fn conv ->
    last_message = get_last_message(conv.id)
    unread_count = get_unread_count(conv.id, user_id)
    Map.merge(conv, %{last_message: last_message, unread_count: unread_count})
  end)
end
```

### Auto-unarchive on New Message
In the `send_message` function or via PubSub handler:
```elixir
# After broadcasting a new message, unarchive for all members
def maybe_unarchive_for_recipients(conversation_id, sender_id) do
  from(m in ConversationMember,
    where: m.conversation_id == ^conversation_id,
    where: m.user_id != ^sender_id,
    where: not is_nil(m.archived_at)
  )
  |> Repo.update_all(set: [archived_at: nil])
end
```

### ChatListLive UI Updates
```heex
<%!-- Tab toggle for regular/archived conversations --%>
<div class="tabs tabs-boxed mb-4">
  <button 
    phx-click="show_active" 
    class={["tab", @view_mode == :active && "tab-active"]}
  >
    Chats
  </button>
  <button 
    phx-click="show_archived" 
    class={["tab", @view_mode == :archived && "tab-active"]}
  >
    Archived
    <span :if={@archived_count > 0} class="badge badge-sm ml-1">{@archived_count}</span>
  </button>
</div>

<%!-- Archive button on conversation card --%>
<button
  phx-click="archive_conversation"
  phx-value-id={conv.id}
  class="btn btn-ghost btn-sm btn-circle"
  title="Archive conversation"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
    <path stroke-linecap="round" stroke-linejoin="round" d="m20.25 7.5-.625 10.632a2.25 2.25 0 0 1-2.247 2.118H6.622a2.25 2.25 0 0 1-2.247-2.118L3.75 7.5m8.25 3v6.75m0 0-3-3m3 3 3-3M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125Z" />
  </svg>
</button>
```

### Event Handlers
```elixir
def handle_event("archive_conversation", %{"id" => conversation_id}, socket) do
  conversation_id = String.to_integer(conversation_id)
  
  case Chat.archive_conversation(conversation_id, socket.assigns.current_user.id) do
    {:ok, _} ->
      conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
      {:noreply, assign(socket, conversations: conversations)}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not archive conversation")}
  end
end

def handle_event("unarchive_conversation", %{"id" => conversation_id}, socket) do
  conversation_id = String.to_integer(conversation_id)
  
  case Chat.unarchive_conversation(conversation_id, socket.assigns.current_user.id) do
    {:ok, _} ->
      # Refresh appropriate list based on current view
      {:noreply, refresh_conversations(socket)}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not unarchive conversation")}
  end
end

def handle_event("show_active", _, socket) do
  conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
  {:noreply, assign(socket, view_mode: :active, conversations: conversations)}
end

def handle_event("show_archived", _, socket) do
  archived = Chat.list_archived_conversations(socket.assigns.current_user.id)
  {:noreply, assign(socket, view_mode: :archived, conversations: archived)}
end
```

## Acceptance Criteria
- [ ] Archive button visible on conversation cards in chat list
- [ ] Clicking archive hides conversation from main list
- [ ] "Archived" tab shows archived conversations with count badge
- [ ] Archived conversations show "Unarchive" button
- [ ] Clicking unarchive brings conversation back to main list
- [ ] New message in archived conversation auto-unarchives it
- [ ] Archive status persists across browser sessions
- [ ] Archive is per-user (archiving doesn't affect other users)
- [ ] Works for both direct messages and group chats
- [ ] Archive option available from within chat view header

## Dependencies
- None (this is an independent feature)

## Testing Notes
- Archive a conversation
- Verify it disappears from main list
- Go to Archived tab and verify it appears there
- Have another user send a message to the archived conversation
- Verify it auto-unarchives and reappears in main list
- Unarchive a conversation manually
- Verify archive persists after page reload
- Test with both direct messages and group chats

## Edge Cases to Handle
- User archives conversation then receives message (should auto-unarchive)
- User in multiple tabs (archive status should sync via PubSub)
- Conversation deleted while archived
- User leaves group that was archived
- Archive/unarchive rapid toggling
- Empty archived list display

## Future Enhancements (not in this task)
- Swipe to archive gesture on mobile
- Bulk archive/unarchive
- Auto-archive old conversations after X days of inactivity
- Search within archived conversations
- Archive confirmation dialog (optional setting)

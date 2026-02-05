# Task: Message Editing and Deletion

## Completion Notes (Agent: 73d2bd6e, Task: aa77696e)

**Completed on: 2026-02-05**

### Implementation Summary:
1. Created migration `20260205044156_add_edited_and_deleted_to_messages.exs` adding `edited_at` and `deleted_at` fields
2. Updated `Message` schema with new fields and changesets (`edit_changeset/2`, `delete_changeset/2`)
3. Added Chat context functions: `get_message!/1`, `can_modify_message?/2`, `edit_message/3`, `delete_message/2`, `broadcast_message_edited/2`, `broadcast_message_deleted/2`
4. Updated `ChatLive` with:
   - New assigns: `editing_message_id`, `edit_content`, `show_delete_modal`, `delete_message_id`
   - Event handlers: `start_edit`, `update_edit`, `save_edit`, `cancel_edit`, `show_delete_modal`, `cancel_delete`, `confirm_delete`
   - PubSub handlers for `{:message_edited, message}` and `{:message_deleted, message}`
   - UI updates showing edit/delete buttons on hover, edit form, deleted message placeholder, confirmation modal
5. Added CSS for message actions styling

### Testing:
- All 106 tests pass
- Fixed a bug where `DateTime.diff/3` was called with mixed DateTime/NaiveDateTime types

---

## Description
Allow users to edit and delete their own messages in conversations. This is a core chat feature that lets users correct mistakes or remove messages they no longer want visible. Edited messages should display an "edited" indicator, and deleted messages should show a "This message was deleted" placeholder (soft delete).

## Requirements
- Users can only edit/delete their own messages (not others')
- Edited messages display an "edited" indicator with a timestamp
- Deleted messages show "This message was deleted" placeholder (soft delete, not hard delete)
- Edit/delete options appear on hover or via a menu on the message
- Edits and deletions are broadcast in real-time to all conversation participants
- Agent messages cannot be edited or deleted
- Time limit for editing/deleting: within 15 minutes of sending (configurable)
- Confirmation dialog before deletion

## Implementation Steps

1. **Update Message schema and migration** (`lib/elixirchat/chat/message.ex`):
   - Add `edited_at` datetime field (nullable, defaults to nil)
   - Add `deleted_at` datetime field (nullable, for soft delete)
   - Add validation functions

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration add_edited_and_deleted_to_messages
   ```
   ```elixir
   alter table(:messages) do
     add :edited_at, :utc_datetime, null: true
     add :deleted_at, :utc_datetime, null: true
   end
   ```

3. **Add edit/delete functions to Chat context** (`lib/elixirchat/chat.ex`):
   - `edit_message/3` - Edit a message (validates ownership & time limit)
   - `delete_message/2` - Soft delete a message (validates ownership & time limit)
   - `can_modify_message?/2` - Check if user can edit/delete a message
   - Helper to check time limit (15 minutes)

4. **Add PubSub broadcasts for edits/deletes**:
   - `broadcast_message_edited/2` - Broadcast edit to conversation
   - `broadcast_message_deleted/2` - Broadcast deletion to conversation

5. **Update ChatLive to handle edit/delete events** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `editing_message_id` to socket assigns (nil when not editing)
   - Handle `"edit_message"` event - show edit input
   - Handle `"save_edit"` event - save the edit
   - Handle `"cancel_edit"` event - cancel editing mode
   - Handle `"delete_message"` event - show confirmation
   - Handle `"confirm_delete"` event - perform deletion
   - Handle `{:message_edited, message}` PubSub message
   - Handle `{:message_deleted, message_id}` PubSub message

6. **Update message rendering in ChatLive**:
   - Add edit/delete buttons (visible on hover or via dropdown menu)
   - Show "edited" indicator for edited messages
   - Show "This message was deleted" for deleted messages
   - Show edit input when editing a message
   - Add confirmation modal for deletion

7. **Add CSS for message actions** (`assets/css/app.css`):
   - Style message action buttons (edit/delete icons)
   - Hover state to reveal actions
   - Edited indicator styling
   - Deleted message placeholder styling

## Technical Details

### Message Modifications Check
```elixir
@edit_delete_time_limit_minutes 15

def can_modify_message?(message, user_id) do
  cond do
    message.sender_id != user_id -> {:error, :not_owner}
    message.deleted_at != nil -> {:error, :already_deleted}
    Agent.is_agent?(message.sender_id) -> {:error, :agent_message}
    !within_time_limit?(message) -> {:error, :time_expired}
    true -> :ok
  end
end

defp within_time_limit?(message) do
  minutes_since = DateTime.diff(DateTime.utc_now(), message.inserted_at, :minute)
  minutes_since <= @edit_delete_time_limit_minutes
end
```

### Edit Message Function
```elixir
def edit_message(message_id, user_id, new_content) do
  message = Repo.get!(Message, message_id)
  
  case can_modify_message?(message, user_id) do
    :ok ->
      message
      |> Message.edit_changeset(%{content: new_content, edited_at: DateTime.utc_now()})
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          updated = Repo.preload(updated, :sender)
          broadcast_message_edited(message.conversation_id, updated)
          {:ok, updated}
        error -> error
      end
    error -> error
  end
end
```

### PubSub Events
```elixir
# Broadcast edit
{:message_edited, %{id: id, content: content, edited_at: edited_at}}

# Broadcast delete
{:message_deleted, %{id: id}}
```

### UI Components

```heex
<%!-- Message with actions --%>
<div class="chat-bubble-wrapper group relative">
  <div :if={message.deleted_at} class="chat-bubble chat-bubble-deleted opacity-60 italic">
    This message was deleted
  </div>
  <div :if={!message.deleted_at} class="chat-bubble">
    {message.content}
    <span :if={message.edited_at} class="text-xs opacity-50 ml-2">(edited)</span>
  </div>
  
  <%!-- Action buttons (only for own messages within time limit) --%>
  <div :if={can_modify?(@current_user.id, message)} class="absolute top-0 right-0 opacity-0 group-hover:opacity-100 transition-opacity">
    <button phx-click="edit_message" phx-value-id={message.id} class="btn btn-ghost btn-xs">
      <svg><!-- edit icon --></svg>
    </button>
    <button phx-click="delete_message" phx-value-id={message.id} class="btn btn-ghost btn-xs text-error">
      <svg><!-- delete icon --></svg>
    </button>
  </div>
</div>
```

## Acceptance Criteria
- [ ] Users can edit their own messages within 15 minutes
- [ ] Users can delete their own messages within 15 minutes
- [ ] Edited messages show "(edited)" indicator
- [ ] Deleted messages show "This message was deleted" placeholder
- [ ] Edit/delete buttons only appear for user's own messages
- [ ] Edit/delete buttons only appear within the time limit
- [ ] Real-time updates: edits/deletes appear instantly for all users
- [ ] Agent messages cannot be edited or deleted
- [ ] Confirmation dialog appears before deletion
- [ ] Cannot edit/delete already deleted messages

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Create a conversation between two users
- Send messages and verify edit/delete buttons appear on hover
- Edit a message and verify "edited" indicator appears
- Verify edit appears in real-time for other user
- Delete a message and verify placeholder appears
- Verify deletion appears in real-time for other user
- Wait 15+ minutes and verify edit/delete buttons disappear
- Verify you cannot edit/delete another user's messages
- Test in both direct and group chats

## Edge Cases
- Editing a message to empty content (should not be allowed)
- Rapid editing (debounce or rate limit)
- Editing while another user is reading the message
- Network issues during edit/delete
- User tries to edit/delete via API after time limit

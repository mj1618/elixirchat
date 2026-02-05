# Task: Message Deletion

## Completion Notes (Agent: 60f83b84, Task: d12ce640)

**Status:** Duplicate task - functionality already implemented in 010-message-edit-delete.completed.md

This task was identified as a duplicate of the message edit/delete task which was already completed. The deletion functionality including soft delete, "This message was deleted" placeholder, real-time broadcasts, and UI is fully implemented.

---

## Description
Add the ability for users to delete their own messages. This is a fundamental chat feature that gives users control over their content. Deleted messages should show a placeholder text like "This message was deleted" to maintain conversation flow context.

## Requirements
- Users can only delete their own messages (not others' messages)
- Deleted messages show "This message was deleted" placeholder instead of content
- Delete action has a confirmation dialog to prevent accidental deletion
- Delete option appears on hover/long-press on the message
- Deletion is "soft delete" - message record stays but content is removed
- System preserves conversation flow (doesn't remove the message entirely)
- Real-time: other users see the deletion immediately via PubSub

## Implementation Steps

1. **Add deleted_at field to Message schema** (`lib/elixirchat/chat/message.ex`):
   - Add `deleted_at` field (datetime, nullable)
   - Create migration for the new column
   - Update changeset for deletion

2. **Create migration** (`priv/repo/migrations/TIMESTAMP_add_deleted_at_to_messages.exs`):
   - Add `deleted_at` datetime column to messages table

3. **Add delete_message function to Chat context** (`lib/elixirchat/chat.ex`):
   - `delete_message/2` - takes message_id and user_id
   - Verifies user owns the message before deleting
   - Sets `deleted_at` timestamp instead of actually deleting
   - Broadcasts deletion event to conversation subscribers
   - Returns appropriate error if user doesn't own message

4. **Add broadcast function for deletions** (`lib/elixirchat/chat.ex`):
   - `broadcast_message_deleted/2` - broadcasts deletion event

5. **Update ChatLive to handle deletions** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `handle_event("delete_message", ...)` to process delete requests
   - Add `handle_info({:message_deleted, ...}, ...)` to receive deletion broadcasts
   - Update assigns to reflect deleted messages in real-time

6. **Update message rendering in ChatLive**:
   - Show delete button (trash icon) on hover for user's own messages
   - Add confirmation modal/dialog before deletion
   - Render deleted messages with placeholder text and distinct styling
   - Hide delete button for messages already deleted

7. **Update chat_live.ex render function**:
   - Add delete button to message UI (only for own messages)
   - Style deleted messages (italic, muted color)
   - Add confirmation modal component

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddDeletedAtToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :deleted_at, :utc_datetime
    end
  end
end
```

### Delete Function
```elixir
def delete_message(message_id, user_id) do
  message = Repo.get!(Message, message_id)
  
  if message.sender_id == user_id do
    message
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()})
    |> Repo.update()
    |> case do
      {:ok, message} ->
        broadcast_message_deleted(message.conversation_id, message_id)
        {:ok, message}
      error ->
        error
    end
  else
    {:error, :unauthorized}
  end
end

def broadcast_message_deleted(conversation_id, message_id) do
  Phoenix.PubSub.broadcast(
    Elixirchat.PubSub,
    "conversation:#{conversation_id}",
    {:message_deleted, %{message_id: message_id}}
  )
end
```

### UI Component - Delete Button
```heex
<button
  :if={message.sender_id == @current_user.id && is_nil(message.deleted_at)}
  phx-click="delete_message"
  phx-value-message-id={message.id}
  data-confirm="Are you sure you want to delete this message?"
  class="opacity-0 group-hover:opacity-100 btn btn-ghost btn-xs text-error"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
    <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
  </svg>
</button>
```

### Deleted Message Display
```heex
<div :if={message.deleted_at} class="chat-bubble bg-base-300 text-base-content/50 italic">
  This message was deleted
</div>
<div :if={is_nil(message.deleted_at)} class={["chat-bubble", get_bubble_class(message, @current_user.id)]}>
  {message.content}
</div>
```

## Acceptance Criteria
- [ ] Users can delete their own messages via a delete button
- [ ] Delete button only appears on user's own messages
- [ ] Confirmation dialog prevents accidental deletion
- [ ] Deleted messages show "This message was deleted" placeholder
- [ ] Deleted messages have distinct visual styling (italic, muted)
- [ ] Other conversation members see deletion in real-time
- [ ] Users cannot delete other users' messages
- [ ] Works in both direct and group chats
- [ ] Agent messages cannot be deleted by regular users

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Create a conversation and send several messages
- Verify delete button appears only on your own messages
- Click delete and confirm the message is replaced with placeholder
- Open same conversation in another browser tab as different user
- Verify the deletion appears in real-time for other users
- Try to delete another user's message (should not be possible)
- Test in group chat with multiple users

## Edge Cases to Handle
- User tries to delete already-deleted message (no-op, graceful handling)
- Message deleted while someone is replying (UX consideration)
- Race condition: two users try to delete same message simultaneously
- Very long conversations with many deleted messages (performance)
- Agent messages should not be deletable by regular users

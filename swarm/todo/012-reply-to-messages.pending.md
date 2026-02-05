# Task: Reply to Messages

## Description
Add the ability to reply to specific messages in a conversation. This feature allows users to reference a previous message when responding, making conversations easier to follow, especially in group chats with multiple threads of discussion. Similar to reply functionality in Slack, Discord, and modern messaging apps.

## Requirements
- Users can reply to any message in a conversation (their own or others')
- Replied-to message shows as a preview above the reply
- Clicking the preview scrolls to the original message
- Reply button appears on hover for each message
- When replying, show a preview of the message being replied to above the input
- Cancel button to clear the reply state
- Replies work in both direct and group chats
- If the original message is deleted, show "Original message was deleted"

## Implementation Steps

1. **Add reply_to_id field to Message schema** (`lib/elixirchat/chat/message.ex`):
   - Add `reply_to_id` field (foreign key to messages table, nullable)
   - Add `reply_to` association (belongs_to self-reference)
   - Update changeset to handle reply_to_id

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration add_reply_to_messages
   ```
   ```elixir
   alter table(:messages) do
     add :reply_to_id, references(:messages, on_delete: :nilify_all)
   end

   create index(:messages, [:reply_to_id])
   ```

3. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Update `send_message/3` to accept optional `reply_to_id`
   - Update `list_messages/2` to preload `reply_to` with sender
   - Ensure reply_to message is from the same conversation (validation)

4. **Update ChatLive to handle replies** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `replying_to` to socket assigns (nil or message struct)
   - Handle `"start_reply"` event - set message being replied to
   - Handle `"cancel_reply"` event - clear reply state
   - Update `"send_message"` to include reply_to_id when set
   - Handle click on reply preview to scroll to original message

5. **Update message rendering in ChatLive**:
   - Add reply button (corner arrow icon) on hover for each message
   - Show reply preview above input when replying
   - Display replied-to message preview above the actual message bubble
   - Style reply preview (smaller, muted, clickable)
   - Handle deleted original messages gracefully

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddReplyToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :reply_to_id, references(:messages, on_delete: :nilify_all)
    end

    create index(:messages, [:reply_to_id])
  end
end
```

### Updated Message Schema
```elixir
schema "messages" do
  field :content, :string
  field :edited_at, :utc_datetime
  field :deleted_at, :utc_datetime
  
  belongs_to :conversation, Conversation
  belongs_to :sender, User
  belongs_to :reply_to, __MODULE__  # Self-reference for replies

  timestamps()
end

def changeset(message, attrs) do
  message
  |> cast(attrs, [:content, :conversation_id, :sender_id, :reply_to_id])
  |> validate_required([:content, :conversation_id, :sender_id])
  # ... other validations
  |> foreign_key_constraint(:reply_to_id)
end
```

### Updated send_message function
```elixir
def send_message(conversation_id, sender_id, content, opts \\ []) do
  reply_to_id = Keyword.get(opts, :reply_to_id)
  
  attrs = %{
    content: content,
    conversation_id: conversation_id,
    sender_id: sender_id,
    reply_to_id: reply_to_id
  }
  
  # Validate reply_to message exists and is in same conversation
  if reply_to_id do
    reply_to = Repo.get(Message, reply_to_id)
    if is_nil(reply_to) or reply_to.conversation_id != conversation_id do
      return {:error, :invalid_reply_to}
    end
  end
  
  %Message{}
  |> Message.changeset(attrs)
  |> Repo.insert()
  # ... rest of function
end
```

### UI Components

```heex
<%!-- Reply button on message hover --%>
<button
  :if={is_nil(message.deleted_at)}
  phx-click="start_reply"
  phx-value-message-id={message.id}
  class="opacity-0 group-hover:opacity-100 btn btn-ghost btn-xs"
  title="Reply"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
    <path stroke-linecap="round" stroke-linejoin="round" d="M9 15 3 9m0 0 6-6M3 9h12a6 6 0 0 1 0 12h-3" />
  </svg>
</button>

<%!-- Reply preview above message bubble --%>
<div :if={message.reply_to} class="flex items-center gap-2 mb-1 text-sm opacity-70 cursor-pointer hover:opacity-100" phx-click="scroll_to_message" phx-value-message-id={message.reply_to_id}>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
    <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 19.5 15-15m0 0H8.25m11.25 0v11.25" />
  </svg>
  <span :if={message.reply_to.deleted_at} class="italic">Original message was deleted</span>
  <span :if={is_nil(message.reply_to.deleted_at)}>
    <strong>{message.reply_to.sender.username}:</strong> {truncate(message.reply_to.content, 50)}
  </span>
</div>

<%!-- Reply indicator above message input --%>
<div :if={@replying_to} class="bg-base-200 p-2 rounded-t-lg flex justify-between items-center">
  <div class="text-sm">
    <span class="opacity-70">Replying to</span>
    <strong class="ml-1">{@replying_to.sender.username}</strong>
    <span class="ml-2 opacity-70 truncate">{truncate(@replying_to.content, 40)}</span>
  </div>
  <button phx-click="cancel_reply" class="btn btn-ghost btn-xs">
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
    </svg>
  </button>
</div>
```

## Acceptance Criteria
- [ ] Reply button appears on hover for each message
- [ ] Clicking reply shows preview above input with cancel button
- [ ] Sending a reply includes reference to original message
- [ ] Replies display with preview of original message above them
- [ ] Clicking reply preview scrolls to original message
- [ ] Works in both direct and group chats
- [ ] If original message is deleted, shows "Original message was deleted"
- [ ] Cannot reply to deleted messages (reply button hidden)
- [ ] Real-time: replies appear correctly for all conversation members

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)
- Task 010: Message Edit/Delete (for handling deleted replied-to messages)

## Testing Notes
- Create a conversation and send several messages
- Click reply on a message, verify preview appears above input
- Send reply and verify it shows with original message preview
- Click on reply preview, verify it scrolls to original message
- Delete a message that has replies, verify replies show "Original message was deleted"
- Test in group chat with multiple users
- Verify replies appear correctly for other users in real-time
- Test canceling a reply

## Edge Cases to Handle
- Reply to a message that gets deleted before you send (handle gracefully)
- Very long original messages (truncate in preview)
- Multiple levels of replies (keep it simple - just show immediate parent)
- Reply to agent message (should work)
- User tries to reply via API to message in different conversation (validate)
- Network issues while sending reply

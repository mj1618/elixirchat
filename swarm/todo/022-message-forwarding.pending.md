# Task: Message Forwarding

## Description
Allow users to forward messages from one conversation to another. This is a common chat feature that enables users to share messages, images, or file attachments across different conversations (both direct messages and group chats). When a message is forwarded, it should be clear that it's a forwarded message, showing the original sender's name.

## Requirements
- Users can forward any non-deleted message to another conversation
- Forward dialog shows a list of conversations the user is a member of
- Forwarded messages display "Forwarded from [original sender]" indicator
- Support forwarding text messages, images, and file attachments
- Multiple messages cannot be forwarded at once (single message only for simplicity)
- Cannot forward to the same conversation the message is already in
- Search/filter functionality in the forward dialog to find conversations quickly

## Implementation Steps

1. **Update Message schema** (`lib/elixirchat/chat/message.ex`):
   - Add `forwarded_from_id` field (references users table, nullable)
   - Add migration for the new field
   - Update changeset to handle forwarded_from_id

2. **Create migration**:
   - Add `forwarded_from_id` to messages table
   - Foreign key to users table
   - Nullable field (only set for forwarded messages)

3. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Add `forward_message/3` function (message_id, target_conversation_id, sender_id)
   - Function should:
     - Verify the user is a member of the target conversation
     - Copy the message content and attachments to the new conversation
     - Set the forwarded_from_id to the original message sender
     - Broadcast the new message to the target conversation

4. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add assigns: `show_forward_modal`, `forward_message_id`, `forward_search_query`, `forward_conversations`
   - Add "Forward" button to message action buttons (visible on hover)
   - Handle events:
     - `"show_forward_modal"` - opens forward dialog
     - `"close_forward_modal"` - closes dialog
     - `"search_forward_conversations"` - filters conversation list
     - `"forward_to_conversation"` - performs the forward action
   - Update message rendering to show "Forwarded from X" indicator

5. **Update UI**:
   - Add forward button to message hover actions
   - Create forward modal with:
     - Search input to filter conversations
     - List of conversations (showing name, last message preview)
     - Cancel and Forward buttons
   - Style forwarded message indicator

6. **Update list_messages preload** (if needed):
   - Ensure `forwarded_from` user is preloaded for display

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddForwardedFromToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :forwarded_from_id, references(:users, on_delete: :nilify_all)
    end

    create index(:messages, [:forwarded_from_id])
  end
end
```

### Message Schema Update
```elixir
# In lib/elixirchat/chat/message.ex
schema "messages" do
  # ... existing fields
  belongs_to :forwarded_from, Elixirchat.Accounts.User
end

def changeset(message, attrs) do
  message
  |> cast(attrs, [:content, :conversation_id, :sender_id, :reply_to_id, :forwarded_from_id])
  # ... rest of changeset
end
```

### Chat Context Function
```elixir
def forward_message(message_id, target_conversation_id, sender_id) do
  message = get_message!(message_id)
  
  # Verify user is member of target conversation
  unless member?(target_conversation_id, sender_id) do
    {:error, :not_a_member}
  else
    # Create forwarded message
    attrs = %{
      content: message.content,
      conversation_id: target_conversation_id,
      sender_id: sender_id,
      forwarded_from_id: message.sender_id
    }
    
    result = 
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()
    
    case result do
      {:ok, new_message} ->
        # Copy attachments if any
        copy_attachments(message.id, new_message.id)
        
        # Update conversation timestamp
        update_conversation_timestamp(target_conversation_id)
        
        # Preload and broadcast
        new_message = Repo.preload(new_message, [:sender, :forwarded_from, :attachments])
        |> Map.put(:reactions_grouped, %{})
        broadcast_message(target_conversation_id, new_message)
        
        {:ok, new_message}
      error -> error
    end
  end
end

defp copy_attachments(source_message_id, target_message_id) do
  attachments = from(a in Attachment, where: a.message_id == ^source_message_id) |> Repo.all()
  
  Enum.each(attachments, fn att ->
    %Attachment{}
    |> Attachment.changeset(%{
      message_id: target_message_id,
      filename: att.filename,
      original_filename: att.original_filename,
      content_type: att.content_type,
      size: att.size
    })
    |> Repo.insert!()
  end)
end
```

### UI - Forward Button (add to message action buttons)
```heex
<%!-- Forward button --%>
<button
  phx-click="show_forward_modal"
  phx-value-message-id={message.id}
  class="btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm"
  title="Forward"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
    <path stroke-linecap="round" stroke-linejoin="round" d="m15 15 6-6m0 0-6-6m6 6H9a6 6 0 0 0 0 12h3" />
  </svg>
</button>
```

### UI - Forward Modal
```heex
<%!-- Forward message modal --%>
<div :if={@show_forward_modal} class="modal modal-open">
  <div class="modal-box">
    <h3 class="font-bold text-lg">Forward Message</h3>
    
    <div class="py-4">
      <input
        type="text"
        placeholder="Search conversations..."
        value={@forward_search_query}
        phx-keyup="search_forward_conversations"
        phx-debounce="300"
        name="query"
        class="input input-bordered w-full mb-4"
        autofocus
      />
      
      <div class="max-h-64 overflow-y-auto space-y-2">
        <div
          :for={conv <- @forward_conversations}
          :if={conv.id != @conversation.id}
          phx-click="forward_to_conversation"
          phx-value-conversation-id={conv.id}
          class="p-3 bg-base-200 rounded-lg cursor-pointer hover:bg-base-300 transition-colors"
        >
          <div class="font-medium">{get_conversation_name(conv, @current_user.id)}</div>
          <div :if={conv.last_message} class="text-sm text-base-content/60 truncate">
            {conv.last_message.content}
          </div>
        </div>
        
        <p :if={@forward_conversations == []} class="text-center text-base-content/60 py-4">
          No conversations found
        </p>
      </div>
    </div>
    
    <div class="modal-action">
      <button phx-click="close_forward_modal" class="btn btn-ghost">Cancel</button>
    </div>
  </div>
  <div class="modal-backdrop bg-base-content/50" phx-click="close_forward_modal"></div>
</div>
```

### UI - Forwarded Message Indicator
```heex
<%!-- Add above message content, after reply preview --%>
<div
  :if={message.forwarded_from}
  class="text-xs opacity-70 mb-1 flex items-center gap-1"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3 flex-shrink-0">
    <path stroke-linecap="round" stroke-linejoin="round" d="m15 15 6-6m0 0-6-6m6 6H9a6 6 0 0 0 0 12h3" />
  </svg>
  <span>Forwarded from <strong>{message.forwarded_from.username}</strong></span>
</div>
```

## Acceptance Criteria
- [ ] Users can forward messages via a button that appears on hover
- [ ] Forward modal shows list of user's conversations
- [ ] Can search/filter conversations in the forward modal
- [ ] Forwarded message appears in target conversation
- [ ] Forwarded message shows "Forwarded from [username]" indicator
- [ ] File attachments are also forwarded correctly
- [ ] Cannot forward deleted messages
- [ ] Cannot forward to the same conversation
- [ ] Flash message confirms successful forward
- [ ] Works for both direct messages and group chats

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)
- Task 014: File Attachments (completed)

## Testing Notes
- Forward a text message to another conversation
- Forward a message with attachments
- Verify forwarded indicator shows original sender name
- Try to forward to the same conversation (should not be allowed or show error)
- Forward between direct message and group chat
- Search for a conversation in forward modal
- Verify forwarded message shows in real-time for other users
- Try to forward a deleted message (should not show forward button)

## Edge Cases to Handle
- Original sender account deleted (show "Unknown User" or similar)
- Target conversation deleted while modal is open
- User removed from target conversation while modal is open
- Very long messages should forward correctly
- Messages with markdown/mentions should preserve formatting
- Link previews should regenerate in target conversation

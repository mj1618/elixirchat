# Task: Read Receipts

## Description
Add read receipts to show when messages have been read by conversation participants. This is a common feature in chat applications like WhatsApp and Messenger that helps users know when their messages have been seen. In direct chats, show read status on individual messages. In group chats, show who has read each message.

## Requirements
- Track when users read messages in a conversation
- In direct chats: show "delivered" then "read" indicator on sent messages
- In group chats: show count of who has read, with option to see names
- Mark messages as read when user views them (scrolls them into view)
- Real-time updates: senders see read status update live via PubSub
- Read receipts should not be retroactive (only track from when feature is enabled)
- Efficient batch updates (don't send individual read events for each message)

## Implementation Steps

1. **Create ReadReceipt schema and migration** (`lib/elixirchat/chat/read_receipt.ex`):
   - Fields: `id`, `message_id`, `user_id`, `read_at` (datetime)
   - Unique constraint on `[:message_id, :user_id]`
   - Belongs to Message and User

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration create_read_receipts
   ```
   ```elixir
   create table(:read_receipts) do
     add :read_at, :utc_datetime, null: false
     add :message_id, references(:messages, on_delete: :delete_all), null: false
     add :user_id, references(:users, on_delete: :delete_all), null: false
     timestamps()
   end

   create unique_index(:read_receipts, [:message_id, :user_id])
   create index(:read_receipts, [:message_id])
   create index(:read_receipts, [:user_id])
   ```

3. **Add read receipt functions to Chat context** (`lib/elixirchat/chat.ex`):
   - `mark_messages_read/3` - Mark multiple messages as read by a user
   - `get_read_status/2` - Get read status for messages in a conversation
   - `get_readers/1` - Get list of users who have read a specific message
   - `broadcast_read_receipt/3` - Broadcast read update to conversation

4. **Update ChatLive to handle read receipts** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add JavaScript hook to detect which messages are visible
   - Handle `"messages_viewed"` event with list of message IDs
   - Handle `{:messages_read, ...}` PubSub message for real-time updates
   - Track read status in socket assigns

5. **Update message rendering**:
   - Add read receipt indicator below/beside sent messages
   - In direct chats: single checkmark (delivered) → double checkmark (read)
   - In group chats: "Read by X" with expandable list
   - Style indicators subtly (small, muted color)

6. **Add JavaScript hook for visibility detection** (`assets/js/app.js`):
   - Use Intersection Observer API to detect visible messages
   - Batch message IDs and send to server periodically (debounced)
   - Only send for messages not yet marked as read

## Technical Details

### ReadReceipt Schema
```elixir
defmodule Elixirchat.Chat.ReadReceipt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "read_receipts" do
    field :read_at, :utc_datetime
    belongs_to :message, Elixirchat.Chat.Message
    belongs_to :user, Elixirchat.Accounts.User

    timestamps()
  end

  def changeset(read_receipt, attrs) do
    read_receipt
    |> cast(attrs, [:read_at, :message_id, :user_id])
    |> validate_required([:read_at, :message_id, :user_id])
    |> unique_constraint([:message_id, :user_id])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
  end
end
```

### Mark Messages Read Function
```elixir
def mark_messages_read(conversation_id, user_id, message_ids) when is_list(message_ids) do
  now = DateTime.utc_now()
  
  # Filter to only messages in this conversation that user hasn't read
  existing_read = from(r in ReadReceipt,
    where: r.user_id == ^user_id and r.message_id in ^message_ids,
    select: r.message_id
  ) |> Repo.all() |> MapSet.new()
  
  new_message_ids = Enum.reject(message_ids, &MapSet.member?(existing_read, &1))
  
  if new_message_ids != [] do
    entries = Enum.map(new_message_ids, fn msg_id ->
      %{message_id: msg_id, user_id: user_id, read_at: now, inserted_at: now, updated_at: now}
    end)
    
    Repo.insert_all(ReadReceipt, entries, on_conflict: :nothing)
    broadcast_messages_read(conversation_id, user_id, new_message_ids)
  end
  
  :ok
end
```

### PubSub Event
```elixir
# Broadcast read receipt update
{:messages_read, %{user_id: user_id, message_ids: [id1, id2, ...]}}
```

### JavaScript Hook for Visibility Detection
```javascript
Hooks.ReadReceipts = {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        const visibleMessageIds = entries
          .filter(e => e.isIntersecting)
          .map(e => e.target.dataset.messageId)
          .filter(id => id && !this.readMessages.has(id));
        
        if (visibleMessageIds.length > 0) {
          visibleMessageIds.forEach(id => this.pendingReads.add(id));
          this.scheduleSendReads();
        }
      },
      { threshold: 0.5 }
    );
    
    this.readMessages = new Set();
    this.pendingReads = new Set();
    this.sendTimeout = null;
    
    // Observe all message elements
    document.querySelectorAll('[data-message-id]').forEach(el => {
      this.observer.observe(el);
    });
  },
  
  scheduleSendReads() {
    if (this.sendTimeout) return;
    this.sendTimeout = setTimeout(() => {
      const ids = Array.from(this.pendingReads);
      if (ids.length > 0) {
        this.pushEvent("messages_viewed", { message_ids: ids });
        ids.forEach(id => this.readMessages.add(id));
        this.pendingReads.clear();
      }
      this.sendTimeout = null;
    }, 500);
  },
  
  destroyed() {
    this.observer.disconnect();
    if (this.sendTimeout) clearTimeout(this.sendTimeout);
  }
}
```

### UI Components

```heex
<%!-- Read receipt indicator for direct chats --%>
<div :if={message.sender_id == @current_user.id} class="text-xs text-base-content/50 flex items-center gap-1">
  <span :if={message_read_by_recipient?(message, @read_receipts, @conversation)}>
    <%!-- Double checkmark (read) --%>
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-primary">
      <path d="M1.5 12.5l5 5 10-10M7.5 12.5l5 5 10-10" stroke="currentColor" stroke-width="2" fill="none"/>
    </svg>
  </span>
  <span :if={!message_read_by_recipient?(message, @read_receipts, @conversation)}>
    <%!-- Single checkmark (delivered) --%>
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
      <path d="M4.5 12.5l5 5 10-10" stroke="currentColor" stroke-width="2" fill="none"/>
    </svg>
  </span>
</div>

<%!-- Read receipt indicator for group chats --%>
<div :if={message.sender_id == @current_user.id && @conversation.is_group} class="text-xs text-base-content/50">
  <% readers = get_message_readers(message.id, @read_receipts) %>
  <span :if={length(readers) > 0} class="cursor-help" title={Enum.map_join(readers, ", ", & &1.username)}>
    Read by {length(readers)}
  </span>
</div>
```

## Acceptance Criteria
- [ ] Read receipts are tracked when messages scroll into view
- [ ] Direct chats show single checkmark (delivered) → double checkmark (read)
- [ ] Group chats show "Read by X" count with names on hover
- [ ] Read status updates in real-time for message sender
- [ ] No duplicate read receipts created
- [ ] Efficient batching of read events (not one per message)
- [ ] Works in both direct and group chats
- [ ] Read receipts persist across page refreshes

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Create a direct chat between two users
- User A sends a message, sees single checkmark
- User B views the message
- User A sees double checkmark appear in real-time
- Test in group chat with 3+ users
- Verify "Read by X" count updates as users view messages
- Hover to see list of readers
- Refresh page and verify read receipts persist
- Send multiple messages and verify batched read receipt updates

## Edge Cases to Handle
- User scrolls past messages very quickly (batch updates)
- User views message while offline (handle on reconnect)
- Message deleted after being read (cascade delete receipts)
- Very large group (truncate reader list in tooltip)
- Performance with many messages (efficient queries)
- User views same message multiple times (no-op)
- Agent messages in conversations (agents don't need read receipts)

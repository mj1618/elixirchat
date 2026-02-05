# Task: Message Threads

## Description
Allow users to reply to messages in a thread, creating organized sub-conversations within the main chat. Threads keep discussions focused and prevent the main conversation from getting cluttered with tangential topics. This is a common feature in Slack, Discord, and other modern chat applications.

## Requirements
- Users can click "Reply in thread" on any message to open a thread view
- Thread replies appear in a side panel or modal, not in the main message list
- A "thread indicator" shows on messages that have thread replies (e.g., "3 replies" badge)
- Clicking the thread indicator opens the thread view
- Thread participants receive notifications for new thread replies
- The original message is shown at the top of the thread view
- Users can optionally "Also send to channel" when replying in a thread (sends to both thread and main chat)
- Thread replies are searchable
- Real-time updates for thread replies via PubSub

## Implementation Steps

1. **Create ThreadReply schema and migration** (`lib/elixirchat/chat/thread_reply.ex`):
   - Fields: `parent_message_id`, `user_id`, `content`, `also_sent_to_channel`
   - Migration for thread_replies table
   - Foreign key to messages table

2. **Update Message schema** (`lib/elixirchat/chat/message.ex`):
   - Add `has_many :thread_replies` association
   - Add virtual field `thread_reply_count` for display

3. **Add thread functions to Chat context** (`lib/elixirchat/chat.ex`):
   - `create_thread_reply/4` - creates a reply in a thread
   - `list_thread_replies/1` - gets all replies for a message
   - `get_thread_reply_count/1` - counts replies for a message
   - `get_messages_with_thread_counts/1` - batch load thread counts for messages
   - Broadcast functions for real-time thread updates

4. **Add thread UI to ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add "Reply in thread" option to message context menu
   - Thread view panel/modal component
   - Thread indicator badge on messages with replies
   - Handle thread-related events (open_thread, close_thread, send_thread_reply)
   - "Also send to channel" checkbox in thread reply form

5. **Add thread subscriptions** for real-time updates:
   - Subscribe to thread updates when viewing a thread
   - Broadcast new thread replies to thread subscribers

## Technical Details

### ThreadReply Schema
```elixir
schema "thread_replies" do
  field :content, :string
  field :also_sent_to_channel, :boolean, default: false
  
  belongs_to :parent_message, Message
  belongs_to :user, User
  
  timestamps()
end
```

### Migration
```elixir
create table(:thread_replies) do
  add :content, :text, null: false
  add :also_sent_to_channel, :boolean, default: false
  add :parent_message_id, references(:messages, on_delete: :delete_all), null: false
  add :user_id, references(:users, on_delete: :delete_all), null: false
  
  timestamps()
end

create index(:thread_replies, [:parent_message_id])
create index(:thread_replies, [:user_id])
```

### Chat Context Functions
```elixir
def create_thread_reply(parent_message_id, user_id, content, opts \\ []) do
  also_send = Keyword.get(opts, :also_send_to_channel, false)
  
  %ThreadReply{}
  |> ThreadReply.changeset(%{
    parent_message_id: parent_message_id,
    user_id: user_id,
    content: content,
    also_sent_to_channel: also_send
  })
  |> Repo.insert()
  |> case do
    {:ok, reply} ->
      broadcast_thread_reply(parent_message_id, reply)
      if also_send, do: create_message_from_thread_reply(reply)
      {:ok, reply}
    error -> error
  end
end

def list_thread_replies(parent_message_id) do
  from(r in ThreadReply,
    where: r.parent_message_id == ^parent_message_id,
    order_by: [asc: r.inserted_at],
    preload: [:user]
  )
  |> Repo.all()
end
```

## Acceptance Criteria
- [ ] Users can open a thread view by clicking "Reply in thread" on any message
- [ ] Thread replies are displayed in chronological order with the parent message at top
- [ ] Messages with thread replies show a reply count badge
- [ ] New thread replies appear in real-time for all thread viewers
- [ ] "Also send to channel" option works correctly
- [ ] Thread replies are included in message search results
- [ ] Thread UI is responsive and works on mobile viewports
- [ ] Thread panel can be closed and reopened without losing context

## Dependencies
- Existing Message schema and Chat context
- PubSub for real-time updates
- Existing message display components

## Testing Notes
- Test with playwright-cli: Open a chat, reply in thread, verify thread view opens
- Test real-time: Open same conversation in two browsers, create thread reply in one
- Test "Also send to channel" creates both thread reply and regular message
- Test thread count badge updates when replies are added

## Edge Cases
- Deleting a parent message should cascade delete all thread replies
- Thread replies should respect blocked users (don't show replies from blocked users)
- Empty threads (0 replies) should not show thread indicator
- Very long threads should be paginated or virtualized

# Task: Direct Chat System

## Description
Implement direct messaging between two users. Users can search for other users by username and start a direct conversation.

## Requirements
- Users can search for other users by username
- Users can start a direct chat with another user
- Users can send and receive messages in real-time (via Phoenix LiveView/PubSub)
- Messages are persisted to the database
- Chat list shows all conversations with the most recent message preview
- Unread message indicators

## Implementation Steps

1. **Create database schema and migrations**:
   - `Elixirchat.Chat.Conversation` schema
     - Fields: `id`, `type` (direct/group), `inserted_at`, `updated_at`
   - `Elixirchat.Chat.ConversationMember` schema
     - Fields: `id`, `conversation_id`, `user_id`, `last_read_at`, `inserted_at`
   - `Elixirchat.Chat.Message` schema
     - Fields: `id`, `conversation_id`, `sender_id`, `content`, `inserted_at`

2. **Create Chat context** (`lib/elixirchat/chat.ex`):
   - `create_direct_conversation/2` - creates conversation between two users
   - `get_or_create_direct_conversation/2` - finds existing or creates new
   - `list_user_conversations/1` - lists all conversations for a user
   - `send_message/3` - creates message and broadcasts via PubSub
   - `list_messages/2` - lists messages in a conversation (paginated)
   - `mark_conversation_read/2` - updates last_read_at for user

3. **Create LiveView pages**:
   - Chat list page at `/chats` showing all conversations
   - Chat page at `/chats/:id` for viewing/sending messages
   - User search component for finding users to chat with

4. **Real-time updates**:
   - Use Phoenix PubSub to broadcast new messages
   - Subscribe to conversation topics on mount
   - Handle incoming messages in handle_info

5. **Update navigation**:
   - Add "Chats" link to authenticated users
   - Redirect to chats page after login

## Acceptance Criteria
- [ ] Logged-in user can search for other users by username
- [ ] Can start a new direct chat with a found user
- [ ] Messages appear in real-time without page refresh
- [ ] Chat list shows all conversations with last message preview
- [ ] Messages are persisted and visible on page reload
- [ ] Cannot access chats when not logged in

## Dependencies
- Task 001: User Authentication System (must be completed first)

## Testing Notes
- Test with two browser windows to verify real-time messaging
- Test that messages persist after page reload
- Verify unauthorized access is blocked

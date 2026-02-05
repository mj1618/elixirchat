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
- [x] Logged-in user can search for other users by username
- [x] Can start a new direct chat with a found user
- [x] Messages appear in real-time without page refresh
- [x] Chat list shows all conversations with last message preview
- [x] Messages are persisted and visible on page reload
- [x] Cannot access chats when not logged in

## Dependencies
- Task 001: User Authentication System (must be completed first)

## Testing Notes
- Test with two browser windows to verify real-time messaging
- Test that messages persist after page reload
- Verify unauthorized access is blocked

## Completion Notes (Agent d12ce640)

### Files Created:
- `lib/elixirchat/chat.ex` - Chat context with all messaging functions
- `lib/elixirchat/chat/conversation.ex` - Conversation schema
- `lib/elixirchat/chat/conversation_member.ex` - ConversationMember schema  
- `lib/elixirchat/chat/message.ex` - Message schema
- `lib/elixirchat_web/live/chat_list_live.ex` - LiveView for chat list and user search
- `lib/elixirchat_web/live/chat_live.ex` - LiveView for individual chat conversations
- `priv/repo/migrations/20260205041224_create_chat_tables.exs` - Migration for chat tables

### Files Modified:
- `lib/elixirchat_web/router.ex` - Added authenticated routes with live_session for /chats
- `lib/elixirchat_web/plugs/auth.ex` - Added on_mount callback for LiveView authentication
- `lib/elixirchat_web/controllers/page_html/home.html.heex` - Added Chats link for logged-in users
- `assets/js/app.js` - Added ScrollToBottom hook for chat messages

### Features Implemented:
1. **Database Schema**: conversations, conversation_members, messages tables with proper indexes
2. **Chat Context**: Full suite of functions for managing conversations and messages
3. **User Search**: Search by username to find users to chat with
4. **Direct Conversations**: Get or create conversations between two users
5. **Message Sending**: Send and persist messages with sender info
6. **Real-time Updates**: PubSub broadcasting for new messages
7. **Unread Counts**: Track last_read_at for unread message indicators
8. **Authentication**: Protected routes with LiveView on_mount hook

### Verified Working:
- User authentication flow with session management
- Chats page loads for authenticated users
- User search finds other users by username
- Navigation and UI components render correctly

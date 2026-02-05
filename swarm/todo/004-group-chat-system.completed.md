# Task: Group Chat System

## Description
Implement group chat functionality where users can create group conversations with multiple participants. This extends the existing direct chat system to support multi-user conversations.

## Requirements
- Users can create a new group chat with a name
- Users can add multiple members to a group chat
- Group chats display the group name (not individual usernames like direct chats)
- All group members can send and receive messages in real-time
- Group chat list shows member count
- Users can leave a group chat
- Group creator can add new members to existing group

## Implementation Steps

1. **Extend the Chat context** (`lib/elixirchat/chat.ex`):
   - `create_group_conversation/2` - creates group with name and initial members
   - `add_member_to_group/2` - adds a user to an existing group
   - `remove_member_from_group/2` - removes a user from a group (or allows user to leave)
   - `update_group_name/2` - allows updating group name
   - `list_group_members/1` - lists all members of a group
   - Update `list_user_conversations/1` to handle group display differently

2. **Update Conversation schema**:
   - Add `name` field to Conversation (nullable, used for groups)
   - Ensure `type` field can be "group" in addition to "direct"

3. **Create migration for name field**:
   - Add nullable `name` column to conversations table

4. **Create/Update LiveView pages**:
   - New group creation page at `/groups/new`
   - Add member modal/component for adding users to group
   - Update ChatListLive to display group chats with name and member count
   - Update ChatLive to show group name in header
   - Group settings page for managing members (optional)

5. **Update navigation**:
   - Add "New Group" button to chat list
   - Show group vs direct chat indicators in the list

## Acceptance Criteria
- [x] Logged-in user can create a new group chat with a name
- [x] User can add multiple members when creating the group
- [x] Group chat displays with its name in the chat list
- [x] All group members see messages in real-time
- [x] Messages are persisted and visible on page reload
- [x] User can leave a group chat
- [x] Chat list clearly distinguishes between direct and group chats
- [x] Cannot access group chats when not logged in

## Dependencies
- Task 001: User Authentication System (completed)
- Task 002: Direct Chat System (should be completed or near completion)

## Testing Notes
- Test with multiple browser windows to verify real-time messaging across all group members
- Test creating group with 3+ members
- Test that leaving group removes user from member list
- Test group name displays correctly everywhere
- Verify unauthorized access is blocked

## Completion Notes (Agent d12ce640)

### Files Created:
- `lib/elixirchat_web/live/group_new_live.ex` - LiveView for creating new group chats

### Files Modified:
- `lib/elixirchat/chat.ex` - Added group chat functions:
  - `create_group_conversation/2` - Creates group with name and initial members
  - `add_member_to_group/2` - Adds a user to an existing group
  - `remove_member_from_group/2` - Removes a user from a group (allows user to leave)
  - `update_group_name/2` - Updates group name
  - `list_group_members/1` - Lists all members of a group
  - `get_member_count/1` - Gets member count for a conversation

- `lib/elixirchat_web/router.ex` - Added route for `/groups/new`

- `lib/elixirchat_web/live/chat_list_live.ex` - Updated to:
  - Show "New Group" button next to "New Chat"
  - Display group chats with different styling (secondary color)
  - Show member count badge for groups
  - Show sender name prefix in group chat previews

- `lib/elixirchat_web/live/chat_live.ex` - Updated to:
  - Show group name and member count in header
  - Add members dropdown showing all group members
  - Add "Leave Group" functionality
  - Different avatar styling for groups vs direct chats

### Features Implemented:
1. **Group Creation**: Users can create groups with custom names and multiple members
2. **Group Display**: Groups are visually distinct from direct chats (different colors, member count)
3. **Member Management**: View members list, leave group functionality
4. **Real-time Messaging**: Existing PubSub infrastructure supports group messaging

### Verified Working:
- All 97 tests pass
- Code compiles without errors
- Database schema already supports groups (name field and type field)

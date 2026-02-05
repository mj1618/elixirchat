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
- [ ] Logged-in user can create a new group chat with a name
- [ ] User can add multiple members when creating the group
- [ ] Group chat displays with its name in the chat list
- [ ] All group members see messages in real-time
- [ ] Messages are persisted and visible on page reload
- [ ] User can leave a group chat
- [ ] Chat list clearly distinguishes between direct and group chats
- [ ] Cannot access group chats when not logged in

## Dependencies
- Task 001: User Authentication System (completed)
- Task 002: Direct Chat System (should be completed or near completion)

## Testing Notes
- Test with multiple browser windows to verify real-time messaging across all group members
- Test creating group with 3+ members
- Test that leaving group removes user from member list
- Test group name displays correctly everywhere
- Verify unauthorized access is blocked

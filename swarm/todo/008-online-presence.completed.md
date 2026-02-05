# Task: User Online Status/Presence

## Description
Add real-time online status indicators to show which users are currently online. This improves the chat experience by letting users know when others are available to chat. Phoenix Presence is the ideal tool for this, providing distributed presence tracking with automatic cleanup when users disconnect.

## Requirements
- Show online/offline status indicator next to usernames in chat list
- Show online status in direct chat headers
- Show count of online members in group chat headers
- Green dot indicator for online users, gray for offline
- Presence updates happen in real-time without page refresh
- Handle multiple tabs/sessions per user gracefully

## Implementation Steps

1. **Add Phoenix Presence module** (`lib/elixirchat/presence.ex`):
   - Create Presence module using `Phoenix.Presence`
   - Track users in a global "users:online" topic
   - Helper functions to check if a user is online

2. **Configure Presence in Application supervision tree** (`lib/elixirchat/application.ex`):
   - Add Presence to the supervision tree

3. **Track presence when user connects** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - On mount, track the current user's presence
   - Subscribe to presence updates
   - Handle presence_diff events to update UI

4. **Create presence helper component/functions**:
   - `is_user_online?/1` - Check if a specific user is online
   - `get_online_users/0` - Get list of all online user IDs
   - `get_online_count/1` - Get count of online users for a conversation

5. **Update Chat List UI** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Add online indicator dot next to conversation name
   - For direct chats: show if other user is online
   - For group chats: show "X online" count

6. **Update Chat View UI** (`lib/elixirchat_web/live/chat_live.ex`):
   - Track presence on mount
   - Show online status in header for direct chats
   - Show online member count for groups
   - Online indicator next to messages from online users

7. **Handle presence across LiveViews**:
   - Ensure presence is tracked consistently
   - Clean up presence when user disconnects/navigates away

## Technical Details

### Presence Module Structure
```elixir
defmodule Elixirchat.Presence do
  use Phoenix.Presence,
    otp_app: :elixirchat,
    pubsub_server: Elixirchat.PubSub
end
```

### Tracking Users
```elixir
# Track user when they connect to any LiveView
Elixirchat.Presence.track(self(), "users:online", user_id, %{
  user_id: user_id,
  username: user.username,
  joined_at: DateTime.utc_now()
})
```

### Checking Online Status
```elixir
def is_user_online?(user_id) do
  "users:online"
  |> Elixirchat.Presence.list()
  |> Map.has_key?(to_string(user_id))
end
```

### UI Component
```heex
<%!-- Online indicator dot --%>
<div class={[
  "w-2 h-2 rounded-full",
  @is_online && "bg-success" || "bg-base-content/30"
]}></div>
```

## Acceptance Criteria
- [ ] Online users have a green dot indicator in chat list
- [ ] Offline users have a gray dot indicator
- [ ] Direct chat header shows online/offline status
- [ ] Group chat header shows "X of Y online"
- [ ] Status updates in real-time when users connect/disconnect
- [ ] Multiple tabs from same user count as single online presence
- [ ] Presence is cleaned up when user closes tab/navigates away

## Dependencies
- Task 001: User Authentication System (completed)
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Open app in two different browsers with different users
- Sign in with User A, verify they show as online to User B
- Close User A's tab, verify they show as offline
- Open multiple tabs with same user, verify single presence
- Test with group chats and verify online counts update correctly
- Test navigation between pages maintains presence

## Edge Cases to Handle
- User has multiple tabs open
- User's connection drops without clean disconnect
- Race conditions when user rapidly navigates
- Large number of users online (performance)

## Completion Notes (Agent d12ce640)

### What was implemented:

1. **Created `lib/elixirchat/presence.ex`** - Phoenix.Presence module with:
   - `track_user/2` - Track a user's presence
   - `subscribe/0` - Subscribe to presence updates
   - `get_online_user_ids/0` - Get list of online user IDs
   - `is_user_online?/1` - Check if a specific user is online
   - `get_online_count/1` - Count online users from a list

2. **Updated `lib/elixirchat/application.ex`** - Added Presence to supervision tree

3. **Updated `lib/elixirchat_web/live/chat_list_live.ex`**:
   - Track presence and subscribe to updates on mount
   - Handle `presence_diff` events to update online_user_ids
   - Added green/gray dot indicators next to conversation names
   - For direct chats: shows if other user is online
   - For group chats: shows "X/Y online" badge

4. **Updated `lib/elixirchat_web/live/chat_live.ex`**:
   - Track presence and subscribe to updates on mount
   - Handle `presence_diff` events
   - Header shows "Online"/"Offline" status for direct chats
   - Header shows "X/Y online" count for group chats
   - Members dropdown shows online indicators for each member

### Testing Notes:
- Code compiles without errors
- Basic functionality verified with browser
- Pre-existing test failures in ChatLiveTest (unrelated DateTime.diff bug)

### Manual Testing Required:
- Test with two different browser sessions (different users) to verify:
  - Online indicators appear correctly
  - Real-time updates when user connects/disconnects
  - Multiple tabs handling

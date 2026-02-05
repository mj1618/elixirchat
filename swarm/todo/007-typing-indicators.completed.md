# Task: Typing Indicators

## Description
Add real-time typing indicators to chat conversations. When a user starts typing a message, other participants in the conversation should see a "User is typing..." indicator. This improves the chat experience by making conversations feel more natural and responsive.

## Requirements
- Show typing indicator when another user is actively typing
- Typing indicator disappears after user stops typing (debounced, ~2-3 seconds)
- Typing indicator disappears immediately when message is sent
- Support multiple users typing simultaneously in group chats
- Minimal server load - use Phoenix PubSub efficiently
- Don't show your own typing indicator to yourself

## Implementation Steps

1. **Add typing state tracking in ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Track `typing_users` as a MapSet of usernames in socket assigns
   - Add debounce timer reference to track when to stop showing indicator
   - Handle incoming `:user_typing` and `:user_stopped_typing` PubSub events

2. **Create typing broadcast functions in Chat context** (`lib/elixirchat/chat.ex`):
   - `broadcast_typing_start/2` - broadcasts that a user started typing
   - `broadcast_typing_stop/2` - broadcasts that a user stopped typing
   - Use existing PubSub topic: `"conversation:#{conversation_id}"`

3. **Update message input handling in ChatLive**:
   - Broadcast typing start on `update_input` event (debounced - only if not already typing)
   - Broadcast typing stop when:
     - Message is sent
     - Input becomes empty
     - After 3 seconds of no typing (client-side debounce with JS hook)

4. **Add JavaScript hook for typing debounce** (`assets/js/app.js`):
   - Create `TypingIndicator` hook
   - Debounce typing events to avoid spamming server
   - Stop typing after 3 seconds of inactivity
   - Clear typing on blur

5. **Update UI to show typing indicator**:
   - Display typing indicator below messages, above input
   - Show "Alice is typing..." for single user
   - Show "Alice and Bob are typing..." for multiple users
   - Add subtle animation (pulsing dots or similar)

## Acceptance Criteria
- [x] When user A starts typing, user B sees "A is typing..."
- [x] Typing indicator disappears after ~3 seconds of no input
- [x] Typing indicator disappears immediately when message is sent
- [x] Multiple typing users are displayed correctly in group chats
- [x] Users don't see their own typing indicator
- [x] Works reliably in both direct and group chats
- [x] No excessive PubSub messages (proper debouncing)

## Completion Notes (Agent ceefbe20)

### Implementation Summary
Implemented typing indicators using a server-side approach instead of the originally planned JavaScript hook:

1. **Chat Context** (`lib/elixirchat/chat.ex`):
   - Added `broadcast_typing_start/2` - broadcasts user typing event via PubSub
   - Added `broadcast_typing_stop/2` - broadcasts user stopped typing event

2. **ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Added `typing_users` (MapSet), `is_typing` (boolean), and `typing_timer` (timer ref) to assigns
   - Handle `:user_typing` and `:user_stopped_typing` PubSub events
   - Handle `:stop_typing` timer message for auto-stopping after 3 seconds
   - Modified `update_input` to broadcast typing start/stop based on input content
   - Modified `send_message` to stop typing when message is sent
   - Added `format_typing_users/1` helper for UI display

3. **UI** (embedded in ChatLive render):
   - Shows "Username is typing..." with animated dots
   - Supports "A and B are typing..." format for multiple users
   - Reserves space for indicator to avoid layout shift

4. **CSS** (`assets/css/app.css`):
   - Added `.typing-dots` animation for blinking dots effect

### Key Design Decisions
- Used server-side debouncing with `Process.send_after/3` instead of JavaScript hook
- Used `phx-debounce="100"` on input to reduce event frequency
- Typing indicator clears when: message sent, input emptied, or 3 second timeout
- Users don't see their own typing indicator (filtered in handle_info)

### Tests Added
- `test/elixirchat/chat_test.exs`: Added 2 tests for typing indicator PubSub broadcasting

### All Tests Passing
99 tests, 0 failures

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (in progress - but core messaging works)

## Testing Notes
- Open two browser windows with different users in the same chat
- Start typing in one window, verify indicator appears in the other
- Stop typing and verify indicator disappears after timeout
- Send a message and verify indicator disappears immediately
- Test with 3+ users in a group chat
- Verify no console errors or excessive network traffic

## Technical Notes

### PubSub Message Format
```elixir
# Start typing
{:user_typing, %{user_id: 123, username: "alice"}}

# Stop typing  
{:user_stopped_typing, %{user_id: 123}}
```

### Example UI Component
```heex
<div :if={MapSet.size(@typing_users) > 0} class="text-sm text-base-content/60 italic px-4 pb-2">
  <span class="typing-indicator">
    {format_typing_users(@typing_users)} typing
    <span class="typing-dots">...</span>
  </span>
</div>
```

### CSS Animation (add to app.css)
```css
.typing-dots {
  animation: blink 1.4s infinite;
}

@keyframes blink {
  0%, 20% { opacity: 0; }
  50% { opacity: 1; }
  80%, 100% { opacity: 0; }
}
```

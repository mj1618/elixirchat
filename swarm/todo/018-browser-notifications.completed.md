# Task: Browser Notifications

## Completion Notes (Agent ceefbe20)

### Implementation Summary
Implemented browser notification support for the chat application:

1. **BrowserNotification JavaScript Hook** (`assets/js/app.js`):
   - Requests notification permission when the chat view mounts
   - Listens for "notify" events from the LiveView server
   - Only shows notifications when tab is unfocused and permission is granted
   - Shows notification with conversation name as title and "sender: message" as body
   - Uses existing `/images/logo.svg` as notification icon
   - Groups notifications by conversation using tag attribute
   - Auto-closes notifications after 5 seconds
   - Clicking notification focuses the window

2. **ChatLive Server Integration** (`lib/elixirchat_web/live/chat_live.ex`):
   - Added `phx-hook="BrowserNotification"` to main chat container
   - Modified `handle_info({:new_message, ...})` to push "notify" events
   - Only sends notifications for messages from other users (not own messages)
   - Includes sender name, truncated message, conversation_id, and conversation_name
   - Added `truncate_for_notification/1` helper for message truncation

### What Was Implemented
- [x] Browser prompts for notification permission when user opens chat
- [x] Notifications appear when receiving message and tab is not focused  
- [x] Notification shows sender name and message preview
- [x] Clicking notification focuses the window
- [x] No notifications for user's own messages
- [x] Works in both direct and group chats
- [x] Attachment-only messages show "[Attachment]"

### What Was Not Implemented (Future Enhancements)
- [ ] Tab title shows unread count badge
- [ ] Notification sound
- [ ] Per-conversation mute settings
- [ ] User preferences UI for notifications

---

## Description
Add browser/desktop notification support so users receive notifications when they get new messages while the chat tab is not focused. This is a fundamental feature in modern chat applications like Slack and Discord that keeps users engaged and responsive. Notifications should include the sender's name, conversation name, and message preview.

## Requirements
- Request notification permission from the user
- Show browser notification when receiving a new message and the tab is not focused
- Notification includes: sender name, message preview (truncated), conversation name
- Clicking notification focuses the chat window and opens that conversation
- Respect user's notification settings (mute/unmute per conversation - future enhancement)
- No notifications for own messages
- Sound alert option (optional but nice to have)
- Works across browsers: Chrome, Firefox, Safari, Edge

## Implementation Steps

1. **Create NotificationSettings module** (`lib/elixirchat/accounts/notification_settings.ex`):
   - Track user's notification preferences (enabled/disabled globally)
   - Could add per-conversation mute later

2. **Add notification permission request in JavaScript** (`assets/js/app.js`):
   - Request notification permission on page load (after login)
   - Store permission state
   - Create Notification hook that handles permission requests

3. **Create browser notification hook** (`assets/js/app.js`):
   - `BrowserNotification` hook to handle push_event from LiveView
   - Check if tab is focused (document.hidden or document.hasFocus())
   - Show browser Notification API notification
   - Handle notification click to focus window and navigate
   - Truncate long messages in preview

4. **Update ChatLive to trigger notifications** (`lib/elixirchat_web/live/chat_live.ex`):
   - When receiving a new message via PubSub, push_event to JS hook
   - Include sender name, message preview, conversation_id
   - Only send notification event if message is from another user

5. **Add notification sound** (optional):
   - Add notification sound file to assets/static/
   - Play sound when notification is shown
   - Add user preference to enable/disable sound

6. **Update user preferences UI** (optional):
   - Add toggle in user settings for notifications
   - Add toggle for notification sounds

## Technical Details

### JavaScript Hook
```javascript
Hooks.BrowserNotification = {
  mounted() {
    // Request permission on mount
    if ("Notification" in window && Notification.permission === "default") {
      Notification.requestPermission();
    }

    this.handleEvent("notify", ({ sender, message, conversation_id, conversation_name }) => {
      // Don't notify if tab is focused
      if (document.hasFocus()) return;
      
      // Don't notify if permission not granted
      if (Notification.permission !== "granted") return;

      const title = conversation_name || sender;
      const body = `${sender}: ${this.truncate(message, 100)}`;
      
      const notification = new Notification(title, {
        body: body,
        icon: "/images/chat-icon.png",
        tag: `conversation-${conversation_id}`,
        renotify: true
      });

      notification.onclick = () => {
        window.focus();
        // Navigate to conversation if needed
        this.pushEvent("navigate_to_conversation", { conversation_id });
        notification.close();
      };

      // Auto-close after 5 seconds
      setTimeout(() => notification.close(), 5000);
    });
  },

  truncate(str, length) {
    if (str.length <= length) return str;
    return str.substring(0, length) + "...";
  }
}
```

### LiveView Push Event
```elixir
# In handle_info for new messages
def handle_info({:new_message, message}, socket) do
  # ... existing message handling ...
  
  # Send notification event if message is from another user
  if message.user_id != socket.assigns.current_user.id do
    socket = push_event(socket, "notify", %{
      sender: message.user.username,
      message: truncate_message(message.content, 100),
      conversation_id: message.conversation_id,
      conversation_name: socket.assigns.conversation.name
    })
  end
  
  {:noreply, socket}
end

defp truncate_message(nil, _), do: "[Attachment]"
defp truncate_message(content, max_length) when byte_size(content) > max_length do
  String.slice(content, 0, max_length) <> "..."
end
defp truncate_message(content, _), do: content
```

### Tab Title Badge (Nice to Have)
```javascript
// Update page title with unread count
Hooks.UnreadBadge = {
  mounted() {
    this.originalTitle = document.title;
    this.unreadCount = 0;

    this.handleEvent("unread_count", ({ count }) => {
      this.unreadCount = count;
      this.updateTitle();
    });

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) {
        // Reset unread when tab becomes visible
        this.unreadCount = 0;
        this.updateTitle();
      }
    });
  },

  updateTitle() {
    if (this.unreadCount > 0) {
      document.title = `(${this.unreadCount}) ${this.originalTitle}`;
    } else {
      document.title = this.originalTitle;
    }
  }
}
```

### Permission Request UI
```heex
<%!-- Show notification permission banner if not granted --%>
<div
  :if={@show_notification_banner}
  id="notification-banner"
  phx-hook="BrowserNotification"
  class="alert alert-info mb-4"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0"></path>
  </svg>
  <span>Enable notifications to know when you receive new messages.</span>
  <button phx-click="request_notifications" class="btn btn-sm btn-primary">Enable</button>
  <button phx-click="dismiss_notification_banner" class="btn btn-sm btn-ghost">Later</button>
</div>
```

## Acceptance Criteria
- [ ] Browser prompts for notification permission when user first logs in
- [ ] Notifications appear when receiving message and tab is not focused
- [ ] Notification shows sender name and message preview
- [ ] Clicking notification focuses the window
- [ ] No notifications for user's own messages
- [ ] Notifications work on Chrome, Firefox, and Safari
- [ ] Tab title shows unread count badge (optional)
- [ ] Notification sound plays (optional)
- [ ] Works in both direct and group chats

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Open chat in one browser window
- Open chat in another window/tab as a different user
- Send a message from one to the other
- Verify notification appears in unfocused window
- Click notification and verify it focuses the correct window
- Test with tab hidden vs focused
- Test permission denied scenario
- Test across different browsers

## Edge Cases to Handle
- User denies notification permission (show unobtrusive reminder)
- User grants then revokes permission
- Multiple notifications in quick succession (group or replace)
- Very long messages (truncate appropriately)
- Attachment-only messages (show "[Attachment]" or similar)
- Multiple tabs open (avoid duplicate notifications)
- Service worker for persistent notifications (future enhancement)
- Mobile browsers with different notification APIs

## Future Enhancements (not in this task)
- Per-conversation mute/unmute settings
- Do Not Disturb mode
- Scheduled quiet hours
- Push notifications via service worker
- Mobile push notifications (PWA)
- Notification history
- Custom notification sounds per conversation

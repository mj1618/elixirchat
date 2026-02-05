# Task: Mute Conversations

## Description
Allow users to mute specific conversations to stop receiving browser notifications from them while still being able to read and send messages. This is a common chat app feature that helps users manage notification overload, especially in busy group chats. Muted conversations should still show unread indicators but should not trigger browser notifications.

## Requirements
- Users can mute/unmute conversations from the chat view
- Mute toggle button in conversation settings/options area
- Muted conversations don't trigger browser notifications
- Muted conversations still receive messages in real-time
- Muted conversations still show in chat list
- Visual indicator showing a conversation is muted (bell-slash icon)
- Mute preference persisted per user per conversation
- Mute status synced across browser tabs/sessions

## Implementation Steps

1. **Add muted field to conversation_members table** (migration):
   - Add `muted_at` field (datetime, nullable)
   - Null = not muted, timestamp = muted at that time
   - Create migration file

2. **Update ConversationMember schema** (`lib/elixirchat/chat/conversation_member.ex`):
   - Add `muted_at` field to schema
   - Add changeset for mute update

3. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Add `mute_conversation/2` function
   - Add `unmute_conversation/2` function
   - Add `is_muted?/2` function
   - Update notification logic to check mute status

4. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add mute toggle button in chat header or settings panel
   - Handle `mute_conversation` and `unmute_conversation` events
   - Show muted indicator icon
   - Load mute status on mount

5. **Update ChatListLive** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Show muted indicator on muted conversations in the list
   - Visual cue like bell-slash icon next to conversation name

6. **Update browser notification logic**:
   - Check mute status before sending notification
   - Don't notify for muted conversations

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddMutedToConversationMembers do
  use Ecto.Migration

  def change do
    alter table(:conversation_members) do
      add :muted_at, :utc_datetime
    end

    create index(:conversation_members, [:user_id, :muted_at])
  end
end
```

### ConversationMember Schema Update
```elixir
schema "conversation_members" do
  field :user_id, :id
  field :conversation_id, :id
  field :muted_at, :utc_datetime
  
  timestamps()
end

def mute_changeset(member, attrs) do
  member
  |> cast(attrs, [:muted_at])
end
```

### Chat Context Functions
```elixir
def mute_conversation(conversation_id, user_id) do
  membership = get_membership(conversation_id, user_id)
  
  if membership do
    membership
    |> ConversationMember.mute_changeset(%{muted_at: DateTime.utc_now()})
    |> Repo.update()
  else
    {:error, :not_a_member}
  end
end

def unmute_conversation(conversation_id, user_id) do
  membership = get_membership(conversation_id, user_id)
  
  if membership do
    membership
    |> ConversationMember.mute_changeset(%{muted_at: nil})
    |> Repo.update()
  else
    {:error, :not_a_member}
  end
end

def is_muted?(conversation_id, user_id) do
  membership = get_membership(conversation_id, user_id)
  membership && membership.muted_at != nil
end

defp get_membership(conversation_id, user_id) do
  Repo.get_by(ConversationMember, 
    conversation_id: conversation_id, 
    user_id: user_id
  )
end
```

### ChatLive Mute Toggle UI
```heex
<%!-- In chat header or options area --%>
<button
  phx-click={if @is_muted, do: "unmute_conversation", else: "mute_conversation"}
  class="btn btn-ghost btn-circle"
  title={if @is_muted, do: "Unmute conversation", else: "Mute conversation"}
>
  <%= if @is_muted do %>
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M9.143 17.082a24.248 24.248 0 0 0 3.844.148m-3.844-.148a23.856 23.856 0 0 1-5.455-1.31 8.964 8.964 0 0 0 2.3-5.542m3.155 6.852a3 3 0 0 0 5.667 1.97m1.965-2.277L21 21m-4.225-4.225a23.81 23.81 0 0 0 3.536-1.003A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6.53 6.53m10.245 10.245L6.53 6.53M3 3l3.53 3.53" />
    </svg>
  <% else %>
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0" />
    </svg>
  <% end %>
</button>
```

### Event Handlers in ChatLive
```elixir
def handle_event("mute_conversation", _, socket) do
  case Chat.mute_conversation(socket.assigns.conversation.id, socket.assigns.current_user.id) do
    {:ok, _} ->
      {:noreply, assign(socket, is_muted: true)}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not mute conversation")}
  end
end

def handle_event("unmute_conversation", _, socket) do
  case Chat.unmute_conversation(socket.assigns.conversation.id, socket.assigns.current_user.id) do
    {:ok, _} ->
      {:noreply, assign(socket, is_muted: false)}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not unmute conversation")}
  end
end
```

### Update Notification Check
In the browser notification logic (likely in ChatLive or a hook), check mute status:
```elixir
# When deciding whether to send browser notification
def should_notify?(conversation_id, user_id) do
  !Chat.is_muted?(conversation_id, user_id)
end
```

Or in the JavaScript hook that handles notifications:
```javascript
// Only show notification if not muted
this.pushEvent("check_mute_status", { conversation_id: id }, (reply) => {
  if (!reply.is_muted) {
    new Notification(title, options);
  }
});
```

## Acceptance Criteria
- [ ] Mute button visible in chat view header
- [ ] Clicking mute silences the conversation
- [ ] Muted conversations don't trigger browser notifications
- [ ] Muted conversations still receive messages in real-time
- [ ] Muted indicator (bell-slash icon) shown in chat header when muted
- [ ] Muted indicator shown in chat list for muted conversations
- [ ] Unmute button restores notifications
- [ ] Mute preference persists across browser sessions
- [ ] Mute preference is per-user (other users unaffected)
- [ ] Works for both direct messages and group chats

## Dependencies
- Task 018: Browser Notifications (completed) - this modifies notification behavior

## Testing Notes
- Enable browser notifications
- Mute a conversation
- Have another user send a message to that conversation
- Verify no browser notification appears
- Verify message still appears in the chat
- Unmute the conversation
- Send another message
- Verify notification now appears
- Test mute persists after page reload
- Test mute indicator visible in both chat view and chat list
- Verify muting one conversation doesn't affect others

## Edge Cases to Handle
- User opens chat in multiple tabs (mute status should sync)
- User mutes then leaves group (membership deleted)
- Conversation deleted while muted
- Mute/unmute rapid toggling
- New message arrives exactly when muting

## Future Enhancements (not in this task)
- Mute for specific duration (1 hour, 1 day, 1 week)
- Mute all conversations at once (Do Not Disturb mode)
- Mute keywords/topics instead of whole conversations
- Different notification levels (mute sounds but show, etc.)
- Schedule mute times (e.g., mute during work hours)

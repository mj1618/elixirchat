# Task: Leave Group Chat

## Status: COMPLETED

## Completion Notes
The Leave Group Chat feature has been fully implemented:

### Backend Implementation (lib/elixirchat/chat.ex):
- `can_leave_group?/2` - Validates if user can leave (not DM, not General, is member)
- `leave_group/2` - Validates, removes member, and broadcasts the event
- `broadcast_member_left/2` - Notifies all conversation members via PubSub

### Frontend Implementation (lib/elixirchat_web/live/chat_live.ex):
- `show_leave_confirm` assign initialized in mount
- Event handlers: `show_leave_confirm`, `cancel_leave`, `leave_group`
- Info handler: `{:member_left, user_id}` - updates member list or redirects if kicked
- UI: "Leave Group" button with confirmation dialog in members panel
- Button hidden for General group (via `!@conversation.is_general` condition)
- After leaving: user redirected to /chats with success message

---

## Description
Allow users to leave group conversations they no longer want to participate in. Currently users can be added to groups but cannot leave them voluntarily. This feature enables users to exit group chats without requiring an admin to remove them. The `remove_member_from_group/2` function already exists in the Chat context but has no UI.

## Requirements
- "Leave Group" button visible in group chat settings/member panel
- Cannot leave direct message conversations (only groups)
- Cannot leave the General group (it's the default group for all users)
- Confirmation dialog before leaving (to prevent accidental leaves)
- After leaving:
  - Conversation disappears from user's chat list
  - User removed from member list (real-time for other members)
  - Existing messages remain visible to other members
  - User cannot send messages to the group anymore
- System message optionally shown: "User left the group" (nice to have)

## Implementation Steps

1. **Update ChatLive for leave group flow** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `show_leave_confirm` assign (boolean, false by default)
   - Handle `"show_leave_confirm"` event - show confirmation dialog
   - Handle `"cancel_leave"` event - hide confirmation dialog
   - Handle `"leave_group"` event - remove user from group
   - Add the leave button and confirmation UI in the members panel
   - Redirect to chat list after leaving

2. **Add broadcast for member left** (`lib/elixirchat/chat.ex`):
   - `broadcast_member_left/2` - notify all conversation members when someone leaves
   - Update `remove_member_from_group/2` to return the user info for broadcasting

3. **Handle leave in ChatLive** (PubSub):
   - Handle `{:member_left, user_id}` message - update member list

4. **Update ChatListLive** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Handle `{:member_left, user_id}` - remove conversation from list if current user left

5. **Add validation** (`lib/elixirchat/chat.ex`):
   - `can_leave_group?/2` - check if user can leave (not General, is member, is group)

## Technical Details

### Can Leave Group Validation
```elixir
def can_leave_group?(conversation_id, user_id) do
  conversation = Repo.get!(Conversation, conversation_id)
  
  cond do
    conversation.type != "group" -> {:error, :not_a_group}
    conversation.is_general == true -> {:error, :cannot_leave_general}
    !member?(conversation_id, user_id) -> {:error, :not_a_member}
    true -> :ok
  end
end
```

### Leave Group with Broadcast
```elixir
def leave_group(conversation_id, user_id) do
  case can_leave_group?(conversation_id, user_id) do
    :ok ->
      case remove_member_from_group(conversation_id, user_id) do
        {:ok, _} ->
          broadcast_member_left(conversation_id, user_id)
          :ok
        error ->
          error
      end
    error ->
      error
  end
end

def broadcast_member_left(conversation_id, user_id) do
  Phoenix.PubSub.broadcast(
    Elixirchat.PubSub,
    "conversation:#{conversation_id}",
    {:member_left, user_id}
  )
end
```

### LiveView Event Handlers
```elixir
def handle_event("show_leave_confirm", _, socket) do
  {:noreply, assign(socket, show_leave_confirm: true)}
end

def handle_event("cancel_leave", _, socket) do
  {:noreply, assign(socket, show_leave_confirm: false)}
end

def handle_event("leave_group", _, socket) do
  conversation_id = socket.assigns.conversation.id
  user_id = socket.assigns.current_user.id
  
  case Chat.leave_group(conversation_id, user_id) do
    :ok ->
      {:noreply,
       socket
       |> put_flash(:info, "You have left the group")
       |> push_navigate(to: ~p"/chat")}
    {:error, :cannot_leave_general} ->
      {:noreply, put_flash(socket, :error, "You cannot leave the General group")}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not leave the group")}
  end
end

def handle_info({:member_left, user_id}, socket) do
  if user_id == socket.assigns.current_user.id do
    # Current user was removed (maybe kicked), redirect away
    {:noreply, push_navigate(socket, to: ~p"/chat")}
  else
    # Someone else left, reload conversation members
    conversation = Chat.get_conversation!(socket.assigns.conversation.id)
    {:noreply, assign(socket, conversation: conversation)}
  end
end
```

### UI Components
```heex
<%!-- In the members panel, after the member list --%>
<div :if={@conversation.type == "group" && !@conversation.is_general} class="p-2 border-t border-base-300">
  <button
    :if={!@show_leave_confirm}
    phx-click="show_leave_confirm"
    class="btn btn-sm btn-error btn-outline w-full"
  >
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-1">
      <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15m3 0l3-3m0 0l-3-3m3 3H9" />
    </svg>
    Leave Group
  </button>
  
  <%!-- Confirmation dialog --%>
  <div :if={@show_leave_confirm} class="space-y-2">
    <p class="text-sm text-warning">Are you sure you want to leave this group?</p>
    <div class="flex gap-2">
      <button phx-click="leave_group" class="btn btn-sm btn-error flex-1">
        Leave
      </button>
      <button phx-click="cancel_leave" class="btn btn-sm btn-ghost flex-1">
        Cancel
      </button>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] "Leave Group" button visible in group chat member panel (not in direct messages)
- [ ] Button not shown for the General group
- [ ] Clicking button shows confirmation dialog
- [ ] Confirming removes user from group
- [ ] User redirected to chat list after leaving
- [ ] Conversation disappears from user's chat list
- [ ] Other members see updated member list in real-time
- [ ] User cannot rejoin without being re-added by a member
- [ ] Success message shown after leaving

## Dependencies
- Task 004: Group Chat System (completed)
- Task 019: Add Members to Existing Group (useful but not required)

## Testing Notes
- Create a group chat with 3 users
- As one user, click "Leave Group" in the member panel
- Verify confirmation dialog appears
- Confirm and verify:
  - Redirected to chat list
  - Group no longer in chat list
- Log in as another member and verify:
  - Left user no longer in member list
  - Can still see all previous messages
- Verify cannot leave the General group (button should not appear)
- Verify cannot leave a direct message conversation (button should not appear)

## Edge Cases to Handle
- User tries to leave while already removed (race condition)
- User is the last member (allow leaving, group becomes empty)
- Network failure during leave (show error, allow retry)
- User opens multiple tabs and leaves in one (handle in other tabs)
- User with many conversations (performance of chat list update)

## Future Enhancements (not in this task)
- System message "User left the group" shown in chat
- Admin can "kick" members (remove them without their consent)
- Re-join via invite link
- Archive instead of leave (keep history but hide from list)
- "Delete conversation" for groups with no other members

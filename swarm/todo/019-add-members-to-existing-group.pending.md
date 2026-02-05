# Task: Add Members to Existing Group

## Description
Allow group members to invite new users to an existing group conversation. Currently, members can only be added when creating a new group. This feature enables groups to grow over time by adding new participants without recreating the conversation. The UI should be accessible from the group chat's member panel.

## Requirements
- Any group member can add new members to the group
- Add member button visible in the group members panel/dropdown
- Search for users by username (similar to new group creation)
- Cannot add users who are already members
- Cannot add yourself (already in group)
- New members can see full message history
- Real-time update: new member appears in member list for all users
- New member gets the conversation in their chat list immediately

## Implementation Steps

1. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - `add_member_to_group/2` already exists - verify it works correctly
   - Add `broadcast_member_added/3` to notify all conversation members
   - Add validation to prevent adding existing members

2. **Update ChatLive for add member flow** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `show_add_member` assign (boolean, false by default)
   - Add `add_member_search_query` assign
   - Add `add_member_search_results` assign
   - Handle `"toggle_add_member"` event - show/hide the add member UI
   - Handle `"search_members_to_add"` event - search users not in group
   - Handle `"add_member_to_group"` event - add selected user
   - Handle `{:member_added, member}` PubSub message - update member list
   - Add the add member UI in the members panel

3. **Add search function for potential members** (`lib/elixirchat/chat.ex`):
   - `search_users_not_in_conversation/3` - search users by username excluding current members

4. **Update member panel UI** (in ChatLive render):
   - Add "Add Member" button in the members dropdown
   - Add search input when adding members
   - Show search results with "Add" button for each user
   - Show success/error feedback

5. **Add PubSub broadcast for new member**:
   - Broadcast to all conversation members when someone is added
   - Update member list in real-time

## Technical Details

### Search Users Not In Conversation
```elixir
def search_users_not_in_conversation(query, conversation_id, limit \\ 10) do
  existing_member_ids =
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id,
      select: m.user_id
    )
    |> Repo.all()

  from(u in User,
    where: ilike(u.username, ^"%#{query}%"),
    where: u.id not in ^existing_member_ids,
    limit: ^limit,
    order_by: u.username
  )
  |> Repo.all()
end
```

### PubSub Broadcast for Member Added
```elixir
def broadcast_member_added(conversation_id, new_member) do
  Phoenix.PubSub.broadcast(
    Elixirchat.PubSub,
    "conversation:#{conversation_id}",
    {:member_added, new_member}
  )
end
```

### LiveView Event Handlers
```elixir
def handle_event("toggle_add_member", _, socket) do
  {:noreply, assign(socket,
    show_add_member: !socket.assigns.show_add_member,
    add_member_search_query: "",
    add_member_search_results: []
  )}
end

def handle_event("search_members_to_add", %{"query" => query}, socket) do
  results = 
    if String.length(query) >= 2 do
      Chat.search_users_not_in_conversation(query, socket.assigns.conversation.id)
    else
      []
    end
  
  {:noreply, assign(socket,
    add_member_search_query: query,
    add_member_search_results: results
  )}
end

def handle_event("add_member_to_group", %{"user-id" => user_id}, socket) do
  conversation_id = socket.assigns.conversation.id
  user_id = String.to_integer(user_id)
  
  case Chat.add_member_to_group(conversation_id, user_id) do
    {:ok, member} ->
      Chat.broadcast_member_added(conversation_id, member)
      {:noreply,
       socket
       |> put_flash(:info, "Member added successfully")
       |> assign(show_add_member: false, add_member_search_results: [])}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not add member")}
  end
end

def handle_info({:member_added, member}, socket) do
  # Reload conversation with members
  conversation = Chat.get_conversation!(socket.assigns.conversation.id)
  {:noreply, assign(socket, conversation: conversation)}
end
```

### UI Components
```heex
<%!-- In the members panel dropdown --%>
<div :if={@conversation.type == "group"} class="p-2 border-t border-base-300">
  <button
    :if={!@show_add_member}
    phx-click="toggle_add_member"
    class="btn btn-sm btn-primary w-full"
  >
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-1">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19 7.5v3m0 0v3m0-3h3m-3 0h-3m-2.25-4.125a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zM4 19.235v-.11a6.375 6.375 0 0112.75 0v.109A12.318 12.318 0 0110.374 21c-2.331 0-4.512-.645-6.374-1.766z" />
    </svg>
    Add Member
  </button>
  
  <div :if={@show_add_member} class="space-y-2">
    <form phx-change="search_members_to_add" phx-submit="search_members_to_add">
      <input
        type="text"
        name="query"
        value={@add_member_search_query}
        placeholder="Search by username..."
        class="input input-sm input-bordered w-full"
        phx-debounce="300"
        autofocus
      />
    </form>
    
    <div :if={@add_member_search_results != []} class="max-h-40 overflow-y-auto space-y-1">
      <div
        :for={user <- @add_member_search_results}
        class="flex items-center justify-between p-2 bg-base-200 rounded"
      >
        <span class="text-sm font-medium">{user.username}</span>
        <button
          phx-click="add_member_to_group"
          phx-value-user-id={user.id}
          class="btn btn-xs btn-primary"
        >
          Add
        </button>
      </div>
    </div>
    
    <p :if={@add_member_search_query != "" && @add_member_search_results == []} class="text-xs text-base-content/70 text-center py-2">
      No users found
    </p>
    
    <button phx-click="toggle_add_member" class="btn btn-sm btn-ghost w-full">
      Cancel
    </button>
  </div>
</div>
```

## Acceptance Criteria
- [ ] "Add Member" button visible in group chat member panel
- [ ] Clicking button shows search input
- [ ] Can search users by username
- [ ] Search results exclude existing members
- [ ] Clicking "Add" adds user to the group
- [ ] New member appears in member list immediately (real-time)
- [ ] New member sees the conversation in their chat list
- [ ] New member can see full message history
- [ ] Success feedback shown after adding member
- [ ] Works in group chats only (not direct messages)

## Dependencies
- Task 004: Group Chat System (completed)

## Testing Notes
- Create a group chat with 2 users
- As one user, open the group chat
- Click "Add Member" in the members panel
- Search for a third user by username
- Add the user and verify they appear in the member list
- Log in as the new member and verify:
  - The group appears in their chat list
  - They can see all previous messages
  - They can send new messages
- Verify other group members see the new member in real-time

## Edge Cases to Handle
- Search for user that's already in the group (should not appear in results)
- Add member while they're online (should update their chat list immediately)
- Try to add member to a direct message (should not show Add Member button)
- Empty search query (show nothing or all non-members?)
- User tries to add themselves (should not appear in search)
- Network failure during add (show error, allow retry)
- Very long usernames (handle gracefully in UI)

## Future Enhancements (not in this task)
- Admin roles - only admins can add members
- Invite links - generate shareable invite URL
- Pending invites - user must accept invite to join
- Batch add members - add multiple users at once
- Remove members (kick) - admin can remove members

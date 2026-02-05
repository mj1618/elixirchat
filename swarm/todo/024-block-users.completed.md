# Task: Block Users

## Description
Allow users to block other users from contacting them. When a user is blocked:
- The blocked user cannot send direct messages to the blocker
- The blocked user cannot see the blocker's online status
- Existing conversations with blocked users are hidden from the chat list (like archived, but automatic)
- The blocker can still see and unblock users from a "Blocked Users" settings page
- Blocking is one-directional (User A blocking User B doesn't mean B blocks A)

This is a critical safety feature for any chat application, allowing users to prevent unwanted contact from other users.

## Requirements
- Users can block other users from:
  - The user's profile (if viewing profile is implemented)
  - The direct message chat header/settings
  - A "Blocked Users" section in settings
- Blocked users cannot initiate new conversations with the blocker
- Blocked users cannot send messages to existing direct conversations with the blocker
- Messages from blocked users in group chats are still visible (group chats are different)
- The blocker can view a list of blocked users and unblock them
- Blocking someone does not notify them (silent block)
- Users cannot block themselves

## Implementation Steps

1. **Create BlockedUser schema and migration** (`lib/elixirchat/accounts/blocked_user.ex`):
   - Fields: `id`, `blocker_id`, `blocked_id`, `blocked_at`
   - Belongs to User (blocker and blocked)
   - Unique constraint on `[:blocker_id, :blocked_id]`
   - Create migration file

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration create_blocked_users
   ```
   ```elixir
   create table(:blocked_users) do
     add :blocked_at, :utc_datetime, null: false
     add :blocker_id, references(:users, on_delete: :delete_all), null: false
     add :blocked_id, references(:users, on_delete: :delete_all), null: false
     timestamps()
   end

   create unique_index(:blocked_users, [:blocker_id, :blocked_id])
   create index(:blocked_users, [:blocked_id])
   ```

3. **Add block functions to Accounts context** (`lib/elixirchat/accounts.ex`):
   - `block_user/2` - Block a user (blocker_id, blocked_id)
   - `unblock_user/2` - Unblock a user
   - `is_blocked?/2` - Check if blocker has blocked blocked_id
   - `is_blocked_by?/2` - Check if user_id is blocked by other_id
   - `list_blocked_users/1` - Get all users blocked by user_id
   - `get_blocked_user_ids/1` - Get blocked user IDs as MapSet for fast lookup

4. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Modify `send_message/4` to check for blocks in direct conversations
   - Modify `get_or_create_direct_conversation/2` to check for blocks
   - Optionally: filter blocked users from appearing in user search

5. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add "Block User" option in direct message chat settings/header dropdown
   - Handle `block_user` and `unblock_user` events
   - Show blocked indicator if trying to message blocked/blocking user

6. **Create BlockedUsersLive** (`lib/elixirchat_web/live/blocked_users_live.ex`):
   - Settings page to view and manage blocked users
   - List all blocked users with unblock button
   - Search functionality to find blocked users

7. **Update Router** (`lib/elixirchat_web/router.ex`):
   - Add route for `/settings/blocked` -> BlockedUsersLive

8. **Update User Search** (optional but recommended):
   - Don't show blocked users in search results for starting new conversations

## Technical Details

### BlockedUser Schema
```elixir
defmodule Elixirchat.Accounts.BlockedUser do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User

  schema "blocked_users" do
    field :blocked_at, :utc_datetime

    belongs_to :blocker, User
    belongs_to :blocked, User

    timestamps()
  end

  def changeset(blocked_user, attrs) do
    blocked_user
    |> cast(attrs, [:blocked_at, :blocker_id, :blocked_id])
    |> validate_required([:blocked_at, :blocker_id, :blocked_id])
    |> validate_not_self_block()
    |> unique_constraint([:blocker_id, :blocked_id], message: "user already blocked")
    |> foreign_key_constraint(:blocker_id)
    |> foreign_key_constraint(:blocked_id)
  end

  defp validate_not_self_block(changeset) do
    blocker_id = get_field(changeset, :blocker_id)
    blocked_id = get_field(changeset, :blocked_id)

    if blocker_id && blocked_id && blocker_id == blocked_id do
      add_error(changeset, :blocked_id, "cannot block yourself")
    else
      changeset
    end
  end
end
```

### Accounts Context Functions
```elixir
alias Elixirchat.Accounts.BlockedUser

def block_user(blocker_id, blocked_id) do
  %BlockedUser{}
  |> BlockedUser.changeset(%{
    blocker_id: blocker_id,
    blocked_id: blocked_id,
    blocked_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })
  |> Repo.insert()
end

def unblock_user(blocker_id, blocked_id) do
  from(b in BlockedUser,
    where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
  )
  |> Repo.delete_all()

  :ok
end

def is_blocked?(blocker_id, blocked_id) do
  from(b in BlockedUser,
    where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
  )
  |> Repo.exists?()
end

def is_blocked_by?(user_id, other_id) do
  # Check if other_id has blocked user_id
  is_blocked?(other_id, user_id)
end

def list_blocked_users(user_id) do
  from(b in BlockedUser,
    where: b.blocker_id == ^user_id,
    join: u in assoc(b, :blocked),
    preload: [blocked: u],
    order_by: [desc: b.blocked_at]
  )
  |> Repo.all()
end

def get_blocked_user_ids(user_id) do
  from(b in BlockedUser,
    where: b.blocker_id == ^user_id,
    select: b.blocked_id
  )
  |> Repo.all()
  |> MapSet.new()
end
```

### Chat Context Updates
```elixir
# In send_message, add block check for direct conversations
def send_message(conversation_id, sender_id, content, opts \\ []) do
  conversation = get_conversation!(conversation_id)
  
  # Check for blocks in direct conversations
  if conversation.type == "direct" do
    other_user = get_other_user(conversation, sender_id)
    
    cond do
      Accounts.is_blocked?(sender_id, other_user.id) ->
        {:error, :user_blocked}
      
      Accounts.is_blocked_by?(sender_id, other_user.id) ->
        {:error, :blocked_by_user}
      
      true ->
        do_send_message(conversation_id, sender_id, content, opts)
    end
  else
    do_send_message(conversation_id, sender_id, content, opts)
  end
end

# In get_or_create_direct_conversation, check blocks
def get_or_create_direct_conversation(user1_id, user2_id) do
  cond do
    Accounts.is_blocked?(user1_id, user2_id) ->
      {:error, :user_blocked}
    
    Accounts.is_blocked_by?(user1_id, user2_id) ->
      {:error, :blocked_by_user}
    
    true ->
      # existing implementation...
  end
end
```

### UI - Block Button in Chat Header
```heex
<%!-- In chat header dropdown/options menu for direct conversations --%>
<div :if={@conversation.type == "direct"} class="dropdown dropdown-end">
  <label tabindex="0" class="btn btn-ghost btn-circle btn-sm">
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5ZM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5ZM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5Z" />
    </svg>
  </label>
  <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52 z-50">
    <li>
      <button phx-click="block_user" phx-value-user-id={@other_user.id} class="text-error">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
          <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636" />
        </svg>
        Block User
      </button>
    </li>
  </ul>
</div>
```

### BlockedUsersLive Page
```elixir
defmodule ElixirchatWeb.BlockedUsersLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Accounts

  def mount(_params, _session, socket) do
    blocked_users = Accounts.list_blocked_users(socket.assigns.current_user.id)
    {:ok, assign(socket, blocked_users: blocked_users)}
  end

  def handle_event("unblock", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    Accounts.unblock_user(socket.assigns.current_user.id, user_id)
    
    blocked_users = Accounts.list_blocked_users(socket.assigns.current_user.id)
    {:noreply, 
     socket
     |> assign(blocked_users: blocked_users)
     |> put_flash(:info, "User unblocked")}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen">
      <div class="navbar bg-base-100 border-b border-base-300">
        <.link navigate={~p"/chat"} class="btn btn-ghost btn-sm">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
        </.link>
        <h1 class="text-xl font-bold">Blocked Users</h1>
      </div>
      
      <div class="flex-1 overflow-y-auto p-4">
        <div :if={@blocked_users == []} class="text-center text-base-content/60 py-8">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-12 h-12 mx-auto mb-2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636" />
          </svg>
          <p>No blocked users</p>
          <p class="text-sm">When you block someone, they'll appear here</p>
        </div>
        
        <div class="space-y-2">
          <div :for={blocked <- @blocked_users} class="flex items-center justify-between p-3 bg-base-100 rounded-lg border border-base-300">
            <div class="flex items-center gap-3">
              <div class="avatar placeholder">
                <div class="bg-neutral text-neutral-content rounded-full w-10">
                  <span>{String.first(blocked.blocked.username) |> String.upcase()}</span>
                </div>
              </div>
              <div>
                <div class="font-medium">{blocked.blocked.username}</div>
                <div class="text-xs text-base-content/60">
                  Blocked {Calendar.strftime(blocked.blocked_at, "%b %d, %Y")}
                </div>
              </div>
            </div>
            <button
              phx-click="unblock"
              phx-value-user-id={blocked.blocked.id}
              class="btn btn-ghost btn-sm"
            >
              Unblock
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
```

## Acceptance Criteria
- [ ] Users can block other users from direct message chat options
- [ ] Blocked users cannot send direct messages to the blocker
- [ ] Blocked users cannot initiate new conversations with the blocker
- [ ] Block status is not shown to the blocked user (silent)
- [ ] Users can view a list of blocked users in settings
- [ ] Users can unblock users from the blocked users list
- [ ] Blocking does not affect group chats (blocked users can still message in groups)
- [ ] Users cannot block themselves
- [ ] Block persists across sessions
- [ ] Appropriate error messages shown when trying to message a blocking/blocked user

## Dependencies
- Task 002: Direct Chat System (completed)

## Testing Notes
- Block a user and try to send them a direct message (should fail with error)
- Have blocked user try to send you a message (should fail)
- Try to start a new conversation with blocked user (should fail)
- View blocked users list and verify blocked user appears
- Unblock user and verify messaging works again
- Verify group chat messages from blocked users are still visible
- Try to block yourself (should not be allowed)
- Block user, refresh page, verify still blocked

## Edge Cases to Handle
- User tries to block themselves
- Blocking a user they've already blocked (idempotent)
- Unblocking a user that isn't blocked
- User is in group chat with blocked user (should still see their messages)
- Blocking the AI agent (should probably not be allowed)
- Both users block each other
- User deletes account after being blocked (cascade delete)
- Error handling when block/unblock fails

---

## Completion Notes (Agent: ceefbe20)

### Implementation Summary
Implemented the block users feature with the following components:

1. **BlockedUser Schema** (`lib/elixirchat/accounts/blocked_user.ex`)
   - Fields: blocker_id, blocked_id, blocked_at
   - Validates users cannot block themselves
   - Unique constraint on blocker/blocked pair

2. **Database Migration** (`priv/repo/migrations/20260205053726_create_blocked_users.exs`)
   - Created blocked_users table with foreign keys and indexes

3. **Accounts Context Functions** (`lib/elixirchat/accounts.ex`)
   - block_user/2, unblock_user/2
   - is_blocked?/2, is_blocked_by?/2
   - list_blocked_users/1, get_blocked_user_ids/1, get_blocker_ids/1
   - check_block_status/2 (checks both directions)

4. **Chat Context Updates** (`lib/elixirchat/chat.ex`)
   - Updated get_or_create_direct_conversation/2 to check for blocks
   - Updated send_message/4 to check for blocks in direct conversations
   - Updated search_users/3 to optionally exclude blocked users

5. **ChatLive UI Updates** (`lib/elixirchat_web/live/chat_live.ex`)
   - Added is_other_user_blocked assign
   - Added toggle_block_user event handler
   - Added block user button in chat header (only for direct conversations)
   - Added error messages for blocked message sends

6. **BlockedUsersLive Page** (`lib/elixirchat_web/live/blocked_users_live.ex`)
   - Lists all blocked users with unblock functionality
   - Accessible from Settings > Privacy > Blocked Users

7. **Router Update** (`lib/elixirchat_web/router.ex`)
   - Added /settings/blocked route

8. **Settings Page Update** (`lib/elixirchat_web/live/settings_live.ex`)
   - Added Privacy section with link to Blocked Users page

### Testing
- Code compiles successfully
- Basic UI tested with playwright-cli

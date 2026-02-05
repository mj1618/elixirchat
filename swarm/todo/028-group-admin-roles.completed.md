# Task: Group Admin Roles

## Completion Notes (Agent ceefbe20)

Implemented group admin roles feature with the following changes:

1. **Migration** (`priv/repo/migrations/20260205054850_add_role_to_conversation_members.exs`):
   - Added `role` field to conversation_members table (default: "member")
   - Data migration to set oldest member as owner for existing groups

2. **Schema** (`lib/elixirchat/chat/conversation_member.ex`):
   - Added `role` field with validation for "owner", "admin", "member"
   - Added `role_changeset/2` for role updates

3. **Chat Context** (`lib/elixirchat/chat.ex`):
   - Updated `create_group_conversation` to set first member as owner
   - Updated `list_group_members` to return members with roles, sorted by role priority
   - Added admin functions: `kick_member/3`, `promote_to_admin/3`, `demote_from_admin/3`, `transfer_ownership/3`
   - Added helper functions: `get_member_role/2`, `is_admin_or_owner?/2`
   - Updated `can_leave_group?` to check for owner (must transfer first)
   - Added PubSub broadcast functions for role changes

4. **ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Added role badges (Owner/Admin) in member list
   - Added admin controls dropdown (kick, promote, demote, transfer)
   - Added event handlers for all admin actions
   - Added PubSub handlers for real-time role updates
   - Updated leave group UI to warn owners they must transfer first
   - Added transfer ownership confirmation dialog

## Description
Add admin/owner roles to group conversations to enable member management. Currently, groups have no concept of ownership or admin privileges. The user who creates a group should become the owner and have the ability to remove (kick) other members, promote members to admin, and transfer ownership. This is a foundational feature for proper group management.

## Requirements
- Group creator becomes the owner automatically
- Owners can:
  - Remove any member from the group (kick)
  - Promote members to admin role
  - Demote admins back to regular member
  - Transfer ownership to another member
  - All admin abilities
- Admins can:
  - Remove regular members from the group (but not other admins or owner)
  - All regular member abilities
- Regular members can only leave the group themselves
- Display member roles in group member list
- Show "Admin" or "Owner" badge next to names
- Owner cannot leave group without transferring ownership first

## Implementation Steps

1. **Create migration to add role to conversation_members**:
   ```bash
   mix ecto.gen.migration add_role_to_conversation_members
   ```
   - Add `role` field (string, default: "member")
   - Valid values: "owner", "admin", "member"

2. **Update ConversationMember schema** (`lib/elixirchat/chat/conversation_member.ex`):
   - Add `role` field to schema
   - Add validation for role values
   - Add `role_changeset/2` for role updates

3. **Update create_group_conversation** (`lib/elixirchat/chat.ex`):
   - First member added should get role: "owner"
   - Other members get role: "member"

4. **Add admin functions to Chat context** (`lib/elixirchat/chat.ex`):
   - `kick_member/3` - (conversation_id, kicker_user_id, target_user_id)
   - `promote_to_admin/3` - (conversation_id, promoter_user_id, target_user_id)
   - `demote_from_admin/3` - (conversation_id, demoter_user_id, target_user_id)
   - `transfer_ownership/3` - (conversation_id, owner_user_id, new_owner_user_id)
   - `get_member_role/2` - (conversation_id, user_id)
   - `is_admin_or_owner?/2` - (conversation_id, user_id)
   - Update `can_leave_group?/2` to check if owner (must transfer first)

5. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add member management section in group info panel
   - Show role badges next to member names
   - Add kick button for admins/owners
   - Add promote/demote buttons for owners
   - Add transfer ownership option

6. **Add event handlers**:
   - `handle_event("kick_member", ...)` 
   - `handle_event("promote_member", ...)`
   - `handle_event("demote_member", ...)`
   - `handle_event("transfer_ownership", ...)`

7. **Update existing groups** (data migration):
   - Set the oldest member as owner for existing groups
   - Or set first member alphabetically if timestamps are same

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddRoleToConversationMembers do
  use Ecto.Migration

  def change do
    alter table(:conversation_members) do
      add :role, :string, default: "member", null: false
    end

    # Set creator (oldest member) as owner for existing groups
    execute """
      UPDATE conversation_members cm
      SET role = 'owner'
      WHERE cm.id IN (
        SELECT DISTINCT ON (conversation_id) id
        FROM conversation_members
        WHERE conversation_id IN (
          SELECT id FROM conversations WHERE type = 'group'
        )
        ORDER BY conversation_id, inserted_at ASC
      )
    """, ""
  end
end
```

### ConversationMember Schema Update
```elixir
schema "conversation_members" do
  field :last_read_at, :utc_datetime
  field :pinned_at, :utc_datetime
  field :archived_at, :utc_datetime
  field :role, :string, default: "member"

  belongs_to :conversation, Conversation
  belongs_to :user, User

  timestamps()
end

@roles ["owner", "admin", "member"]

def changeset(member, attrs) do
  member
  |> cast(attrs, [:conversation_id, :user_id, :last_read_at, :role])
  |> validate_required([:conversation_id, :user_id])
  |> validate_inclusion(:role, @roles)
  |> foreign_key_constraint(:conversation_id)
  |> foreign_key_constraint(:user_id)
  |> unique_constraint([:conversation_id, :user_id])
end

def role_changeset(member, attrs) do
  member
  |> cast(attrs, [:role])
  |> validate_inclusion(:role, @roles)
end
```

### Chat Context Functions
```elixir
def get_member_role(conversation_id, user_id) do
  from(m in ConversationMember,
    where: m.conversation_id == ^conversation_id and m.user_id == ^user_id,
    select: m.role
  )
  |> Repo.one()
end

def is_admin_or_owner?(conversation_id, user_id) do
  get_member_role(conversation_id, user_id) in ["owner", "admin"]
end

def kick_member(conversation_id, kicker_id, target_id) do
  with :ok <- validate_kick_permission(conversation_id, kicker_id, target_id),
       {:ok, _} <- remove_member_from_group(conversation_id, target_id) do
    broadcast_member_kicked(conversation_id, target_id, kicker_id)
    :ok
  end
end

defp validate_kick_permission(conversation_id, kicker_id, target_id) do
  kicker_role = get_member_role(conversation_id, kicker_id)
  target_role = get_member_role(conversation_id, target_id)

  cond do
    kicker_id == target_id -> {:error, :cannot_kick_self}
    kicker_role == nil -> {:error, :not_a_member}
    target_role == nil -> {:error, :target_not_a_member}
    kicker_role == "member" -> {:error, :not_authorized}
    target_role == "owner" -> {:error, :cannot_kick_owner}
    kicker_role == "admin" and target_role == "admin" -> {:error, :cannot_kick_admin}
    true -> :ok
  end
end

def promote_to_admin(conversation_id, promoter_id, target_id) do
  with :ok <- validate_promote_permission(conversation_id, promoter_id, target_id),
       {:ok, member} <- get_membership(conversation_id, target_id),
       {:ok, updated} <- update_member_role(member, "admin") do
    broadcast_role_change(conversation_id, target_id, "admin")
    {:ok, updated}
  end
end

def transfer_ownership(conversation_id, owner_id, new_owner_id) do
  with :ok <- validate_transfer_permission(conversation_id, owner_id, new_owner_id) do
    Repo.transaction(fn ->
      # Demote current owner to admin
      {:ok, old_owner} = get_membership(conversation_id, owner_id)
      {:ok, _} = update_member_role(old_owner, "admin")
      
      # Promote new owner
      {:ok, new_owner} = get_membership(conversation_id, new_owner_id)
      {:ok, _} = update_member_role(new_owner, "owner")
    end)
    broadcast_ownership_transferred(conversation_id, owner_id, new_owner_id)
    :ok
  end
end
```

### UI - Member List with Roles
```heex
<div :for={member <- @group_members} class="flex items-center justify-between py-2">
  <div class="flex items-center gap-2">
    <img src={avatar_url(member.user)} class="w-8 h-8 rounded-full" />
    <span>{member.user.username}</span>
    <span :if={member.role == "owner"} class="badge badge-primary badge-sm">Owner</span>
    <span :if={member.role == "admin"} class="badge badge-secondary badge-sm">Admin</span>
  </div>
  
  <div :if={@current_user_role in ["owner", "admin"] and member.user_id != @current_user.id}>
    <div class="dropdown dropdown-end">
      <button tabindex="0" class="btn btn-ghost btn-sm btn-circle">
        <svg><!-- more icon --></svg>
      </button>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box shadow w-40">
        <li :if={can_kick?(member, @current_user_role)}>
          <button phx-click="kick_member" phx-value-user-id={member.user_id}>
            Remove from group
          </button>
        </li>
        <li :if={@current_user_role == "owner" and member.role == "member"}>
          <button phx-click="promote_member" phx-value-user-id={member.user_id}>
            Make admin
          </button>
        </li>
        <li :if={@current_user_role == "owner" and member.role == "admin"}>
          <button phx-click="demote_member" phx-value-user-id={member.user_id}>
            Remove admin
          </button>
        </li>
        <li :if={@current_user_role == "owner"}>
          <button phx-click="transfer_ownership" phx-value-user-id={member.user_id}>
            Transfer ownership
          </button>
        </li>
      </ul>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] New groups have creator as owner
- [ ] Existing groups have oldest member set as owner (via migration)
- [ ] Owner badge displays next to owner's name
- [ ] Admin badge displays next to admin names
- [ ] Owner can kick any member (except themselves)
- [ ] Owner can kick admins
- [ ] Admin can kick regular members only
- [ ] Admin cannot kick other admins or owner
- [ ] Owner can promote member to admin
- [ ] Owner can demote admin to member
- [ ] Owner can transfer ownership
- [ ] After transfer, old owner becomes admin
- [ ] Owner cannot leave without transferring ownership first
- [ ] Kicked users are removed from conversation
- [ ] Kicked users receive notification/redirect
- [ ] Role changes broadcast to all members in real-time

## Dependencies
- Task 004: Group Chat System (completed)
- Task 019: Add Members to Existing Group (completed)
- Task 020: Leave Group Chat (completed)

## Testing Notes
- Create a group, verify creator is owner
- Have owner kick a regular member
- Have owner promote member to admin
- Have admin try to kick another admin (should fail)
- Have admin kick a regular member (should succeed)
- Have owner transfer ownership, verify roles swap
- Try to have owner leave without transfer (should fail)
- Check existing groups got an owner assigned

## Edge Cases to Handle
- What happens if kicked user has the conversation open?
- Simultaneous kicks/promotions
- Last admin demoted (OK, owner remains)
- Owner kicks everyone (OK, becomes solo group)
- New member added - should be regular member

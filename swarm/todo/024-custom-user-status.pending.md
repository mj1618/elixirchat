# Task: Custom User Status

## Description
Allow users to set a custom status message that displays alongside their username in the chat. This builds on the existing online presence feature and helps users communicate their availability or current situation (e.g., "In a meeting", "On vacation", "Working from home", "Do not disturb"). The status is visible to other users in conversations and the user list.

## Requirements
- Users can set a custom status message (max 100 characters)
- Status message displays next to username in chat header and conversation list
- Option to select from preset statuses (In a meeting, Away, Do not disturb, etc.)
- Option to write custom text status
- Status can be cleared (no status shown)
- Status persists across sessions (stored in database)
- Online/offline indicator still works independently of status
- Status visible in:
  - User's profile
  - Chat header when viewing conversation with user
  - Conversation list (truncated if long)
  - When hovering over user avatar/name

## Implementation Steps

1. **Add status fields to users table** (migration):
   - Add `status` field (string, max 100 chars, nullable)
   - Add `status_updated_at` field (datetime, nullable)
   - Create migration file

2. **Update User schema** (`lib/elixirchat/accounts/user.ex`):
   - Add `status` field to schema
   - Add `status_updated_at` field
   - Add `status_changeset/2` for updating status

3. **Update Accounts context** (`lib/elixirchat/accounts.ex`):
   - Add `update_user_status/2` function
   - Add `clear_user_status/1` function
   - Add `get_user_with_status/1` function (if needed)

4. **Create UserStatusLive component** or update **SettingsLive**:
   - Status input field with character counter
   - Preset status buttons/dropdown
   - Clear status button
   - Live preview of status
   - Handle events: `set_status`, `clear_status`

5. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Display other user's status in chat header (for direct messages)
   - Subscribe to status updates via PubSub
   - Handle status change broadcasts

6. **Update ChatListLive** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Show status in conversation list items (truncated)
   - Update when status changes

7. **Broadcast status changes**:
   - Use PubSub to broadcast status changes to relevant users
   - Update presence tracking to include status

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :status, :string, size: 100
      add :status_updated_at, :utc_datetime
    end
  end
end
```

### User Schema Update
```elixir
schema "users" do
  # ... existing fields
  field :status, :string
  field :status_updated_at, :utc_datetime
end

def status_changeset(user, attrs) do
  user
  |> cast(attrs, [:status, :status_updated_at])
  |> validate_length(:status, max: 100)
end
```

### Accounts Context Functions
```elixir
def update_user_status(user, status) do
  status = if status == "", do: nil, else: status
  
  user
  |> User.status_changeset(%{
    status: status,
    status_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })
  |> Repo.update()
  |> tap(fn
    {:ok, user} -> broadcast_status_change(user)
    _ -> :ok
  end)
end

def clear_user_status(user) do
  update_user_status(user, nil)
end

defp broadcast_status_change(user) do
  Phoenix.PubSub.broadcast(
    Elixirchat.PubSub,
    "user:#{user.id}:status",
    {:status_changed, user.id, user.status}
  )
end
```

### Preset Status Options
```elixir
@preset_statuses [
  %{emoji: "🟢", text: "Available"},
  %{emoji: "💼", text: "In a meeting"},
  %{emoji: "🏠", text: "Working from home"},
  %{emoji: "🚫", text: "Do not disturb"},
  %{emoji: "🌴", text: "On vacation"},
  %{emoji: "🍔", text: "Out to lunch"},
  %{emoji: "😷", text: "Out sick"},
  %{emoji: "🚗", text: "Commuting"}
]
```

### UI - Status Settings Section
```heex
<div class="form-control">
  <label class="label">
    <span class="label-text font-medium">Status</span>
    <span class="label-text-alt text-base-content/60">
      {String.length(@status_input || "") || 0}/100
    </span>
  </label>
  
  <div class="flex gap-2">
    <input
      type="text"
      value={@status_input}
      phx-change="update_status_input"
      name="status"
      maxlength="100"
      placeholder="What's your status?"
      class="input input-bordered flex-1"
    />
    <button
      :if={@current_user.status}
      phx-click="clear_status"
      class="btn btn-ghost btn-circle"
      title="Clear status"
    >
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
      </svg>
    </button>
  </div>
  
  <div class="flex flex-wrap gap-2 mt-3">
    <button
      :for={preset <- @preset_statuses}
      phx-click="set_preset_status"
      phx-value-status={preset.text}
      phx-value-emoji={preset.emoji}
      class="btn btn-sm btn-outline"
    >
      {preset.emoji} {preset.text}
    </button>
  </div>
</div>
```

### UI - Status Display in Chat Header
```heex
<%!-- In chat header, below username --%>
<div :if={@other_user && @other_user.status} class="text-xs text-base-content/60 truncate max-w-48">
  {@other_user.status}
</div>
```

### UI - Status in Conversation List
```heex
<%!-- Show status in conversation preview --%>
<p :if={conversation.type == "direct" && get_other_user(conversation, @current_user.id).status} 
   class="text-xs text-base-content/50 truncate">
  {get_other_user(conversation, @current_user.id).status}
</p>
```

### Event Handlers
```elixir
def handle_event("set_status", %{"status" => status}, socket) do
  case Accounts.update_user_status(socket.assigns.current_user, status) do
    {:ok, user} ->
      {:noreply, 
       socket
       |> assign(current_user: user, status_input: status)
       |> put_flash(:info, "Status updated")}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not update status")}
  end
end

def handle_event("set_preset_status", %{"status" => text, "emoji" => emoji}, socket) do
  status = "#{emoji} #{text}"
  handle_event("set_status", %{"status" => status}, socket)
end

def handle_event("clear_status", _, socket) do
  case Accounts.clear_user_status(socket.assigns.current_user) do
    {:ok, user} ->
      {:noreply,
       socket
       |> assign(current_user: user, status_input: nil)
       |> put_flash(:info, "Status cleared")}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not clear status")}
  end
end

def handle_event("update_status_input", %{"status" => status}, socket) do
  {:noreply, assign(socket, status_input: status)}
end
```

### PubSub Subscription for Status Changes
```elixir
# Subscribe to status changes for users in current conversation
def subscribe_to_member_statuses(conversation) do
  conversation.members
  |> Enum.each(fn member ->
    Phoenix.PubSub.subscribe(Elixirchat.PubSub, "user:#{member.user_id}:status")
  end)
end

def handle_info({:status_changed, user_id, new_status}, socket) do
  # Update UI to reflect new status
  {:noreply, update_member_status(socket, user_id, new_status)}
end
```

## Acceptance Criteria
- [ ] Status input field in user settings (or dedicated section)
- [ ] Character counter shows remaining characters (max 100)
- [ ] Preset status buttons work and set status immediately
- [ ] Custom text status can be typed and saved
- [ ] Status displays in chat header for direct messages
- [ ] Status displays in conversation list
- [ ] Clear status button removes status
- [ ] Status persists after page refresh
- [ ] Status changes broadcast to other users in real-time
- [ ] Works correctly with online/offline presence indicator
- [ ] Empty status displays nothing (not placeholder text)

## Dependencies
- Task 008: Online Presence (completed) - builds on presence system
- Task 006: User Profile Settings (completed) - adds to settings page

## Testing Notes
- Set a custom status and verify it appears in chat header
- Check status shows in conversation list for other users
- Clear status and verify it's removed everywhere
- Test preset statuses
- Have another user in same conversation verify they see status updates in real-time
- Verify status persists after page refresh
- Test max length (100 chars)
- Test with emojis in status

## Edge Cases to Handle
- Very long status text (truncate with ellipsis in UI)
- Status with only emojis
- Status with special characters
- User changes status while another user is viewing their conversation
- Rapid status changes
- Status cleared while offline

## Future Enhancements (not in this task)
- Status expiration (auto-clear after X hours)
- Status history
- Status scheduling (set status for specific time periods)
- Custom emoji in status
- Link status to calendar integration
- "Busy" status auto-set during meetings

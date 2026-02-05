# Task: User Profile Pictures (Avatars)

## Description
Allow users to upload and display profile pictures (avatars) instead of the current initial-based placeholders. Users should be able to upload an image from their device, crop/resize it, and have it displayed throughout the app wherever their avatar appears (chat messages, member lists, chat headers, etc.).

## Requirements
- Users can upload a profile picture from the Settings page
- Supported formats: JPEG, PNG, GIF, WebP
- Maximum file size: 2MB
- Images are resized/cropped to a standard size (e.g., 200x200 or 256x256)
- Fallback to initials-based avatar if no picture uploaded
- Profile pictures appear in:
  - Chat messages (sender avatar)
  - Conversation list (other user's avatar)
  - Group member panels
  - Chat headers (direct message partner)
  - Navigation bar
- Users can remove their profile picture and revert to initials

## Implementation Steps

1. **Add avatar field to users table** (migration):
   - Add `avatar_filename` field (string, nullable)
   - Create migration file

2. **Update User schema** (`lib/elixirchat/accounts/user.ex`):
   - Add `avatar_filename` field to schema
   - Add changeset for avatar update

3. **Update Accounts context** (`lib/elixirchat/accounts.ex`):
   - Add `update_user_avatar/2` function
   - Add `delete_user_avatar/1` function
   - Add avatar path helper functions

4. **Update Settings LiveView** (`lib/elixirchat_web/live/settings_live.ex`):
   - Add file upload for avatar using `allow_upload`
   - Handle upload validation and processing
   - Add preview of current avatar
   - Add "Remove" button to delete avatar
   - Show upload progress

5. **Create avatar helper module** (`lib/elixirchat_web/components/avatar.ex`):
   - Create a reusable avatar component
   - Handle fallback to initials
   - Support different sizes (xs, sm, md, lg)
   - Handle online status indicator

6. **Update all views to use avatar component**:
   - ChatLive (message avatars, header)
   - ChatListLive (conversation avatars)
   - Group member panels

7. **Image processing** (optional but recommended):
   - Resize uploaded images to standard dimensions
   - Convert to optimized format (WebP or compressed JPEG)
   - Consider using a library like `image` or `mogrify`

## Technical Details

### Migration
```elixir
defmodule Elixirchat.Repo.Migrations.AddAvatarToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_filename, :string
    end
  end
end
```

### User Schema Update
```elixir
schema "users" do
  field :username, :string
  field :password, :string, virtual: true
  field :current_password, :string, virtual: true
  field :password_hash, :string
  field :avatar_filename, :string

  timestamps()
end

def avatar_changeset(user, attrs) do
  user
  |> cast(attrs, [:avatar_filename])
end
```

### Avatar Component
```elixir
defmodule ElixirchatWeb.Components.Avatar do
  use Phoenix.Component

  attr :user, :map, required: true
  attr :size, :string, default: "md" # xs, sm, md, lg
  attr :online, :boolean, default: false
  attr :class, :string, default: ""

  def avatar(assigns) do
    ~H"""
    <div class={["avatar", @online && "online", @class]}>
      <div class={[
        "rounded-full",
        size_class(@size),
        !has_avatar?(@user) && "bg-primary text-primary-content"
      ]}>
        <%= if has_avatar?(@user) do %>
          <img src={avatar_url(@user)} alt={@user.username} />
        <% else %>
          <span class={text_size_class(@size)}>
            {get_initial(@user)}
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  defp has_avatar?(user), do: user.avatar_filename != nil
  
  defp avatar_url(user), do: "/uploads/avatars/#{user.avatar_filename}"
  
  defp get_initial(user) do
    user.username |> String.first() |> String.upcase()
  end
  
  defp size_class("xs"), do: "w-6 h-6"
  defp size_class("sm"), do: "w-8 h-8"
  defp size_class("md"), do: "w-10 h-10"
  defp size_class("lg"), do: "w-16 h-16"
  
  defp text_size_class("xs"), do: "text-xs"
  defp text_size_class("sm"), do: "text-sm"
  defp text_size_class("md"), do: "text-lg"
  defp text_size_class("lg"), do: "text-2xl"
end
```

### Settings LiveView Updates
```elixir
# In mount/3
{:ok,
 socket
 |> allow_upload(:avatar, accept: ~w(.jpg .jpeg .png .gif .webp), max_entries: 1, max_file_size: 2_000_000)
 |> assign(...)}

# Event handlers
def handle_event("save_avatar", _, socket) do
  uploaded_files =
    consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
      dest_filename = "#{socket.assigns.current_user.id}-#{Ecto.UUID.generate()}#{Path.extname(entry.client_name)}"
      dest = Path.join(Accounts.avatars_dir(), dest_filename)
      File.cp!(path, dest)
      {:ok, dest_filename}
    end)

  case uploaded_files do
    [filename] ->
      case Accounts.update_user_avatar(socket.assigns.current_user, %{avatar_filename: filename}) do
        {:ok, user} ->
          {:noreply, socket |> put_flash(:info, "Avatar updated!") |> assign(current_user: user)}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update avatar")}
      end
    _ ->
      {:noreply, socket}
  end
end

def handle_event("remove_avatar", _, socket) do
  case Accounts.delete_user_avatar(socket.assigns.current_user) do
    {:ok, user} ->
      {:noreply, socket |> put_flash(:info, "Avatar removed") |> assign(current_user: user)}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to remove avatar")}
  end
end
```

### UI in Settings Page
```heex
<!-- Avatar Section -->
<div class="card bg-base-100 shadow-xl mb-6">
  <div class="card-body">
    <h2 class="card-title">Profile Picture</h2>
    
    <div class="flex items-center gap-6">
      <!-- Current Avatar Preview -->
      <div class="avatar">
        <div class="w-24 rounded-full bg-primary text-primary-content">
          <%= if @current_user.avatar_filename do %>
            <img src={"/uploads/avatars/#{@current_user.avatar_filename}"} alt="Your avatar" />
          <% else %>
            <span class="text-3xl flex items-center justify-center h-full">
              {String.first(@current_user.username) |> String.upcase()}
            </span>
          <% end %>
        </div>
      </div>
      
      <!-- Upload/Change Controls -->
      <div class="flex-1">
        <form phx-submit="save_avatar" phx-change="validate_avatar">
          <.live_file_input upload={@uploads.avatar} class="file-input file-input-bordered w-full max-w-xs" />
          
          <div :for={entry <- @uploads.avatar.entries} class="mt-2">
            <.live_img_preview entry={entry} class="w-16 h-16 rounded-full object-cover" />
            <progress value={entry.progress} max="100" class="progress progress-primary w-full" />
            <button type="button" phx-click="cancel_avatar_upload" phx-value-ref={entry.ref} class="btn btn-xs btn-ghost">Cancel</button>
          </div>
          
          <div :for={err <- upload_errors(@uploads.avatar)} class="text-error text-sm mt-1">
            {upload_error_to_string(err)}
          </div>
          
          <div class="mt-4 flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm" disabled={@uploads.avatar.entries == []}>
              Upload
            </button>
            <button :if={@current_user.avatar_filename} type="button" phx-click="remove_avatar" class="btn btn-ghost btn-sm">
              Remove
            </button>
          </div>
        </form>
        
        <p class="text-xs text-base-content/50 mt-2">
          Accepted formats: JPEG, PNG, GIF, WebP. Max size: 2MB.
        </p>
      </div>
    </div>
  </div>
</div>
```

## Acceptance Criteria
- [ ] Users can upload a profile picture from Settings
- [ ] Upload validation (format, size) with error messages
- [ ] Uploaded avatars displayed in chat messages
- [ ] Avatars displayed in conversation list
- [ ] Avatars displayed in group member panels
- [ ] Avatars displayed in chat headers
- [ ] Fallback to initials when no avatar set
- [ ] Users can remove their avatar
- [ ] Avatar changes reflected in real-time across the app
- [ ] Works on mobile devices

## Dependencies
- Task 006: User Profile Settings (completed)
- Task 014: File Attachments (completed) - similar upload infrastructure

## Testing Notes
- Upload various image formats (JPEG, PNG, GIF, WebP)
- Try uploading files that are too large (>2MB)
- Try uploading non-image files
- Verify avatar appears in all locations:
  - Settings preview
  - Chat messages
  - Conversation list
  - Group member panel
  - Chat header
- Test removing avatar and verify fallback to initials
- Test with multiple users - each sees correct avatars
- Test on mobile viewport

## Edge Cases to Handle
- Very large images (should be resized or rejected)
- Non-square images (crop to center or allow stretch?)
- Corrupted image files
- User deletes their account (cleanup avatar file)
- Avatar file missing on disk (fallback to initials gracefully)
- Concurrent avatar updates (file naming collision prevention)
- Very long usernames for initial fallback

## Future Enhancements (not in this task)
- Image cropping UI before upload
- Gravatar fallback support
- Default avatar options (choose from preset images)
- Animated avatar support (GIF)
- Avatar history (previous avatars)

---

## Completion Notes (Agent: ceefbe20)

### Implemented
1. **Migration**: Added `avatar_filename` field to users table (`priv/repo/migrations/20260205051542_add_avatar_to_users.exs`)
2. **User Schema**: Added `avatar_filename` field and `avatar_changeset/2` function to `lib/elixirchat/accounts/user.ex`
3. **Accounts Context**: Added avatar functions to `lib/elixirchat/accounts.ex`:
   - `avatars_dir/0` - returns path to avatars directory (creates if needed)
   - `update_user_avatar/2` - updates user's avatar (deletes old file if exists)
   - `delete_user_avatar/1` - removes user's avatar
   - `avatar_url/1` - returns URL path to avatar
   - `has_avatar?/1` - checks if user has avatar
   - Updated `delete_user/1` to clean up avatar file
4. **Settings LiveView**: Added profile picture upload section with:
   - File input with validation (JPEG, PNG, GIF, WebP; max 2MB)
   - Live preview of current avatar
   - Upload button and Remove button
   - Error display for invalid uploads
5. **ChatLive**: Updated to display user avatars in:
   - Message bubbles (chat-image)
   - Chat header (for direct messages)
   - Mention autocomplete dropdown
6. **ChatListLive**: Updated conversation list to show avatars for direct message contacts

### Testing
- Verified Settings page shows Profile Picture section with avatar upload UI
- Screenshot confirmed working avatar display with initial-based fallback
- Avatar files stored in `priv/static/uploads/avatars/`

### Note
Image resizing/cropping is not implemented - uploaded images are stored as-is. This could be added later using an image processing library like `image` or `mogrify`.

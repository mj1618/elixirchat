defmodule ElixirchatWeb.SettingsLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Accounts

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    password_changeset = Accounts.change_user_password(current_user)

    {:ok,
     socket
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       max_file_size: 2_000_000
     )
     |> assign(
       password_form: to_form(password_changeset, as: "password"),
       current_password: "",
       show_delete_modal: false,
       delete_confirmation: "",
       status_input: current_user.status || "",
       preset_statuses: Accounts.preset_statuses()
     )}
  end

  # Upload error helpers - must be defined before render for HEEx compilation
  defp upload_error_to_string(:too_large), do: "File too large (max 2MB)"
  defp upload_error_to_string(:too_many_files), do: "Only one file allowed"
  defp upload_error_to_string(:not_accepted), do: "File type not allowed. Use JPEG, PNG, GIF, or WebP."
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="navbar bg-base-100 shadow-sm">
        <div class="flex-1">
          <.link href={~p"/chats"} class="btn btn-ghost text-xl">Elixirchat</.link>
        </div>
        <div class="flex-none">
          <span class="mr-4">Hello, <strong>{@current_user.username}</strong></span>
          <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm">
            Log Out
          </.link>
        </div>
      </div>

      <Layouts.flash_group flash={@flash} />

      <div class="max-w-2xl mx-auto p-4">
        <div class="flex items-center gap-4 mb-6">
          <.link navigate={~p"/chats"} class="btn btn-ghost btn-sm">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18" />
            </svg>
            Back
          </.link>
          <h1 class="text-2xl font-bold">Settings</h1>
        </div>

        <!-- Profile Picture Section -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Profile Picture</h2>

            <div class="flex items-center gap-6">
              <!-- Current Avatar Preview -->
              <div class="avatar avatar-placeholder">
                <div class="w-24 h-24 rounded-full bg-primary text-primary-content flex items-center justify-center">
                  <%= if @current_user.avatar_filename do %>
                    <img src={"/uploads/avatars/#{@current_user.avatar_filename}"} alt="Your avatar" class="rounded-full w-full h-full object-cover" />
                  <% else %>
                    <span class="text-3xl">
                      {String.first(@current_user.username) |> String.upcase()}
                    </span>
                  <% end %>
                </div>
              </div>

              <!-- Upload/Change Controls -->
              <div class="flex-1">
                <form id="avatar-form" phx-submit="save_avatar" phx-change="validate_avatar">
                  <.live_file_input upload={@uploads.avatar} class="file-input file-input-bordered w-full max-w-xs" />

                  <div :for={entry <- @uploads.avatar.entries} class="mt-2 flex items-center gap-2">
                    <.live_img_preview entry={entry} class="w-16 h-16 rounded-full object-cover" />
                    <progress value={entry.progress} max="100" class="progress progress-primary w-32" />
                    <button type="button" phx-click="cancel_avatar_upload" phx-value-ref={entry.ref} class="btn btn-xs btn-ghost">
                      Cancel
                    </button>
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

        <!-- Profile Section -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Profile</h2>
            <div class="form-control">
              <label class="label">
                <span class="label-text">Username</span>
              </label>
              <input
                type="text"
                value={@current_user.username}
                class="input input-bordered w-full"
                disabled
              />
              <label class="label">
                <span class="label-text-alt text-base-content/50">Username cannot be changed</span>
              </label>
            </div>
          </div>
        </div>

        <!-- Status Section -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Status</h2>
            <p class="text-sm text-base-content/70 mb-2">Let others know what you're up to</p>

            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Current Status</span>
                <span class="label-text-alt text-base-content/60">
                  {String.length(@status_input)}/100
                </span>
              </label>

              <form phx-submit="set_status" class="flex gap-2">
                <input
                  type="text"
                  name="status"
                  value={@status_input}
                  phx-change="update_status_input"
                  maxlength="100"
                  placeholder="What's your status?"
                  class="input input-bordered flex-1"
                />
                <button type="submit" class="btn btn-primary">
                  Set
                </button>
                <button
                  :if={@current_user.status}
                  type="button"
                  phx-click="clear_status"
                  class="btn btn-ghost btn-circle"
                  title="Clear status"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
                  </svg>
                </button>
              </form>

              <div :if={@current_user.status} class="mt-2 p-2 bg-base-200 rounded-lg flex items-center gap-2">
                <span class="text-sm text-base-content/70">Current:</span>
                <span class="font-medium">{@current_user.status}</span>
              </div>
            </div>

            <div class="divider my-2">Preset Statuses</div>

            <div class="flex flex-wrap gap-2">
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
        </div>

        <!-- Change Password Section -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Change Password</h2>

            <.form
              for={@password_form}
              id="password-form"
              phx-submit="change_password"
              phx-change="validate_password"
              class="space-y-4"
            >
              <div class="form-control">
                <label class="label" for="current_password">
                  <span class="label-text">Current Password</span>
                </label>
                <input
                  type="password"
                  name="current_password"
                  id="current_password"
                  value={@current_password}
                  class="input input-bordered w-full"
                  placeholder="Enter your current password"
                  required
                />
              </div>

              <.input
                field={@password_form[:password]}
                type="password"
                label="New Password"
                placeholder="Enter new password (min 6 characters)"
                required
              />

              <div class="form-control mt-4">
                <button type="submit" class="btn btn-primary">
                  Update Password
                </button>
              </div>
            </.form>
          </div>
        </div>

        <!-- Privacy Settings -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Privacy</h2>
            <p class="text-base-content/70">
              Manage your blocked users and privacy settings.
            </p>
            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/settings/blocked"} class="btn btn-outline">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 mr-2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636" />
                </svg>
                Blocked Users
              </.link>
            </div>
          </div>
        </div>

        <!-- Danger Zone -->
        <div class="card bg-base-100 shadow-xl border-2 border-error/20">
          <div class="card-body">
            <h2 class="card-title text-error">Danger Zone</h2>
            <p class="text-base-content/70">
              Once you delete your account, there is no going back. Please be certain.
            </p>
            <div class="card-actions justify-end mt-4">
              <button phx-click="show_delete_modal" class="btn btn-error btn-outline">
                Delete Account
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Delete Confirmation Modal -->
      <div :if={@show_delete_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg text-error">Delete Account</h3>
          <p class="py-4">
            This action cannot be undone. This will permanently delete your account and remove all your data.
          </p>
          <p class="mb-4">
            Type <strong>delete my account</strong> to confirm:
          </p>
          <input
            type="text"
            phx-keyup="update_delete_confirmation"
            value={@delete_confirmation}
            class="input input-bordered w-full"
            placeholder="Type 'delete my account'"
          />
          <div class="modal-action">
            <button phx-click="hide_delete_modal" class="btn">Cancel</button>
            <button
              phx-click="delete_account"
              class="btn btn-error"
              disabled={@delete_confirmation != "delete my account"}
            >
              Delete Account
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="hide_delete_modal"></div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate_avatar", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_avatar_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  @impl true
  def handle_event("save_avatar", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        # Generate unique filename with user ID prefix
        ext = Path.extname(entry.client_name)
        dest_filename = "#{socket.assigns.current_user.id}-#{Ecto.UUID.generate()}#{ext}"
        dest = Path.join(Accounts.avatars_dir(), dest_filename)
        File.cp!(path, dest)
        {:ok, dest_filename}
      end)

    case uploaded_files do
      [filename] ->
        case Accounts.update_user_avatar(socket.assigns.current_user, %{avatar_filename: filename}) do
          {:ok, user} ->
            {:noreply,
             socket
             |> put_flash(:info, "Avatar updated!")
             |> assign(current_user: user)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update avatar")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_avatar", _params, socket) do
    case Accounts.delete_user_avatar(socket.assigns.current_user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Avatar removed")
         |> assign(current_user: user)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove avatar")}
    end
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    password_params = Map.get(params, "password", %{})

    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_password(password_params)
      |> Map.put(:action, :validate)

    current_password = Map.get(params, "current_password", "")

    {:noreply, assign(socket, password_form: to_form(changeset, as: "password"), current_password: current_password)}
  end

  @impl true
  def handle_event("change_password", params, socket) do
    password_params = Map.get(params, "password", %{})
    current_password = Map.get(params, "current_password", "")

    case Accounts.update_user_password(socket.assigns.current_user, current_password, password_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated successfully!")
         |> assign(
           password_form: to_form(Accounts.change_user_password(socket.assigns.current_user), as: "password"),
           current_password: ""
         )}

      {:error, :invalid_current_password} ->
        {:noreply, put_flash(socket, :error, "Current password is incorrect")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, as: "password"))}
    end
  end

  @impl true
  def handle_event("show_delete_modal", _, socket) do
    {:noreply, assign(socket, show_delete_modal: true, delete_confirmation: "")}
  end

  @impl true
  def handle_event("hide_delete_modal", _, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_confirmation: "")}
  end

  @impl true
  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, delete_confirmation: value)}
  end

  @impl true
  def handle_event("delete_account", _, socket) do
    if socket.assigns.delete_confirmation == "delete my account" do
      case Accounts.delete_user(socket.assigns.current_user) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Your account has been deleted.")
           |> redirect(to: ~p"/logout")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete account. Please try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  # ===============================
  # Status Handlers
  # ===============================

  @impl true
  def handle_event("update_status_input", %{"status" => status}, socket) do
    {:noreply, assign(socket, status_input: status)}
  end

  @impl true
  def handle_event("set_status", %{"status" => status}, socket) do
    case Accounts.update_user_status(socket.assigns.current_user, status) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user, status_input: user.status || "")
         |> put_flash(:info, "Status updated")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update status")}
    end
  end

  @impl true
  def handle_event("set_preset_status", %{"status" => text, "emoji" => emoji}, socket) do
    status = "#{emoji} #{text}"

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

  @impl true
  def handle_event("clear_status", _, socket) do
    case Accounts.clear_user_status(socket.assigns.current_user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user, status_input: "")
         |> put_flash(:info, "Status cleared")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not clear status")}
    end
  end

end

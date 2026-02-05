defmodule ElixirchatWeb.SettingsLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Accounts

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    password_changeset = Accounts.change_user_password(current_user)

    {:ok,
     assign(socket,
       password_form: to_form(password_changeset, as: "password"),
       current_password: "",
       show_delete_modal: false,
       delete_confirmation: ""
     )}
  end

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
  def handle_event("validate_password", %{"password" => password_params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_password(password_params)
      |> Map.put(:action, :validate)

    current_password = Map.get(password_params, "current_password", "")

    {:noreply, assign(socket, password_form: to_form(changeset, as: "password"), current_password: current_password)}
  end

  @impl true
  def handle_event("change_password", %{"password" => password_params, "current_password" => current_password}, socket) do
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
end

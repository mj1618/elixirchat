defmodule ElixirchatWeb.BlockedUsersLive do
  @moduledoc """
  LiveView for managing blocked users.
  Users can view their blocked users list and unblock them from here.
  """
  use ElixirchatWeb, :live_view

  alias Elixirchat.Accounts

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    blocked_users = Accounts.list_blocked_users(current_user.id)

    {:ok, assign(socket, blocked_users: blocked_users)}
  end

  @impl true
  def handle_event("unblock", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    current_user = socket.assigns.current_user

    Accounts.unblock_user(current_user.id, user_id)

    blocked_users = Accounts.list_blocked_users(current_user.id)

    {:noreply,
     socket
     |> assign(blocked_users: blocked_users)
     |> put_flash(:info, "User unblocked")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-base-200">
      <%!-- Header --%>
      <div class="navbar bg-base-100 border-b border-base-300 flex-shrink-0">
        <div class="flex-none">
          <.link navigate={~p"/chats"} class="btn btn-ghost btn-sm">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
            </svg>
          </.link>
        </div>
        <div class="flex-1">
          <h1 class="text-xl font-bold">Blocked Users</h1>
        </div>
        <div class="flex-none">
          <ElixirchatWeb.Layouts.theme_toggle />
        </div>
      </div>

      <%!-- Main content --%>
      <div class="flex-1 overflow-y-auto p-4">
        <div class="max-w-2xl mx-auto">
          <%!-- Empty state --%>
          <div :if={@blocked_users == []} class="text-center py-12">
            <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-base-300 flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-8 h-8 text-base-content/50">
                <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636" />
              </svg>
            </div>
            <h2 class="text-lg font-semibold text-base-content/70">No blocked users</h2>
            <p class="text-sm text-base-content/50 mt-1">
              When you block someone, they'll appear here
            </p>
          </div>

          <%!-- Blocked users list --%>
          <div :if={@blocked_users != []} class="space-y-2">
            <p class="text-sm text-base-content/70 mb-4">
              Blocked users cannot send you direct messages or start new conversations with you.
            </p>

            <div
              :for={blocked <- @blocked_users}
              class="flex items-center justify-between p-4 bg-base-100 rounded-lg border border-base-300"
            >
              <div class="flex items-center gap-3">
                <div class="avatar avatar-placeholder">
                  <div class={[
                    "rounded-full w-12 h-12 flex items-center justify-center",
                    !blocked.blocked.avatar_filename && "bg-neutral text-neutral-content"
                  ]}>
                    <%= if blocked.blocked.avatar_filename do %>
                      <img src={"/uploads/avatars/#{blocked.blocked.avatar_filename}"} alt={blocked.blocked.username} class="rounded-full w-full h-full object-cover" />
                    <% else %>
                      <span class="text-lg">{String.first(blocked.blocked.username) |> String.upcase()}</span>
                    <% end %>
                  </div>
                </div>
                <div>
                  <div class="font-medium">{blocked.blocked.username}</div>
                  <div class="text-xs text-base-content/60">
                    Blocked {format_date(blocked.blocked_at)}
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
    </div>
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end

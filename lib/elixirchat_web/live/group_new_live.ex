defmodule ElixirchatWeb.GroupNewLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       group_name: "",
       search_query: "",
       search_results: [],
       selected_members: [],
       error: nil
     )}
  end

  @impl true
  def handle_event("update_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, group_name: name)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    current_user_id = socket.assigns.current_user.id
    selected_ids = Enum.map(socket.assigns.selected_members, & &1.id)
    
    results = 
      Chat.search_users(query, current_user_id)
      |> Enum.reject(fn user -> user.id in selected_ids end)

    {:noreply, assign(socket, search_results: results, search_query: query)}
  end

  @impl true
  def handle_event("add_member", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    user = Enum.find(socket.assigns.search_results, &(&1.id == user_id))

    if user do
      selected = socket.assigns.selected_members ++ [user]
      results = Enum.reject(socket.assigns.search_results, &(&1.id == user_id))
      {:noreply, assign(socket, selected_members: selected, search_results: results)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_member", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    selected = Enum.reject(socket.assigns.selected_members, &(&1.id == user_id))
    {:noreply, assign(socket, selected_members: selected)}
  end

  @impl true
  def handle_event("create_group", _, socket) do
    name = String.trim(socket.assigns.group_name)
    selected = socket.assigns.selected_members
    current_user = socket.assigns.current_user

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Please enter a group name")}

      length(selected) == 0 ->
        {:noreply, assign(socket, error: "Please add at least one member")}

      true ->
        # Include current user in the member list
        member_ids = [current_user.id | Enum.map(selected, & &1.id)]

        case Chat.create_group_conversation(name, member_ids) do
          {:ok, conversation} ->
            {:noreply, push_navigate(socket, to: "/chats/#{conversation.id}")}

          {:error, _} ->
            {:noreply, assign(socket, error: "Could not create group")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="navbar bg-base-100 shadow-sm">
        <div class="flex-none">
          <.link navigate={~p"/chats"} class="btn btn-ghost btn-sm">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
            </svg>
          </.link>
        </div>
        <div class="flex-1">
          <span class="text-xl font-semibold">New Group Chat</span>
        </div>
      </div>

      <div class="max-w-2xl mx-auto p-4">
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <div :if={@error} class="alert alert-error mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>{@error}</span>
            </div>

            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text font-semibold">Group Name</span>
              </label>
              <input
                type="text"
                value={@group_name}
                placeholder="Enter group name..."
                class="input input-bordered w-full"
                phx-change="update_name"
                phx-debounce="100"
                name="name"
              />
            </div>

            <div class="divider">Members</div>

            <div :if={@selected_members != []} class="mb-4">
              <label class="label">
                <span class="label-text font-semibold">Selected Members ({length(@selected_members)})</span>
              </label>
              <div class="flex flex-wrap gap-2">
                <div
                  :for={user <- @selected_members}
                  class="badge badge-primary gap-2 p-3"
                >
                  {user.username}
                  <button
                    phx-click="remove_member"
                    phx-value-user-id={user.id}
                    class="btn btn-ghost btn-xs"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              </div>
            </div>

            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text font-semibold">Add Members</span>
              </label>
              <form phx-change="search" phx-submit="search">
                <input
                  type="text"
                  name="query"
                  value={@search_query}
                  placeholder="Search users by username..."
                  class="input input-bordered w-full"
                  phx-debounce="300"
                />
              </form>
            </div>

            <div :if={@search_results != []} class="space-y-2 mb-4">
              <div
                :for={user <- @search_results}
                class="flex items-center justify-between p-3 bg-base-200 rounded-lg"
              >
                <div class="flex items-center gap-3">
                  <div class="avatar placeholder">
                    <div class="bg-neutral text-neutral-content rounded-full w-8">
                      <span class="text-sm">{String.first(user.username) |> String.upcase()}</span>
                    </div>
                  </div>
                  <span class="font-medium">{user.username}</span>
                </div>
                <button
                  phx-click="add_member"
                  phx-value-user-id={user.id}
                  class="btn btn-sm btn-primary"
                >
                  Add
                </button>
              </div>
            </div>

            <p :if={@search_query != "" && @search_results == []} class="text-base-content/70 text-center py-4">
              No users found matching "{@search_query}"
            </p>

            <div class="card-actions justify-end mt-4">
              <.link navigate={~p"/chats"} class="btn btn-ghost">Cancel</.link>
              <button phx-click="create_group" class="btn btn-primary">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 mr-1">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
                </svg>
                Create Group
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

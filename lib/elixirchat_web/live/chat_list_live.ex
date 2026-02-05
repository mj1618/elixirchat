defmodule ElixirchatWeb.ChatListLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat

  @impl true
  def mount(_params, _session, socket) do
    # current_user is already assigned by on_mount hook
    current_user = socket.assigns.current_user
    conversations = Chat.list_user_conversations(current_user.id)

    {:ok,
     assign(socket,
       conversations: conversations,
       search_query: "",
       search_results: [],
       show_search: false
     )}
  end

  @impl true
  def handle_event("toggle_search", _, socket) do
    {:noreply, assign(socket, show_search: !socket.assigns.show_search, search_results: [], search_query: "")}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results = Chat.search_users(query, socket.assigns.current_user.id)
    {:noreply, assign(socket, search_results: results, search_query: query)}
  end

  @impl true
  def handle_event("start_chat", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    current_user_id = socket.assigns.current_user.id

    case Chat.get_or_create_direct_conversation(current_user_id, user_id) do
      {:ok, conversation} ->
        {:noreply, push_navigate(socket, to: "/chats/#{conversation.id}")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start conversation")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="navbar bg-base-100 shadow-sm">
        <div class="flex-1">
          <.link href="/" class="btn btn-ghost text-xl">Elixirchat</.link>
        </div>
        <div class="flex-none gap-2">
          <span class="mr-2">Hello, <strong>{@current_user.username}</strong></span>
          <.link navigate={~p"/settings"} class="btn btn-ghost btn-sm">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z" />
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
            </svg>
            Settings
          </.link>
          <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm">
            Log Out
          </.link>
        </div>
      </div>

      <div class="max-w-2xl mx-auto p-4">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-2xl font-bold">Chats</h1>
          <button phx-click="toggle_search" class="btn btn-primary btn-sm">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 mr-1">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            New Chat
          </button>
        </div>

        <div :if={@show_search} class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Find a user to chat with</h2>
            <form phx-change="search" phx-submit="search">
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search by username..."
                class="input input-bordered w-full"
                phx-debounce="300"
                autofocus
              />
            </form>

            <div :if={@search_results != []} class="mt-4">
              <div :for={user <- @search_results} class="flex items-center justify-between p-3 hover:bg-base-200 rounded-lg">
                <span class="font-medium">{user.username}</span>
                <button
                  phx-click="start_chat"
                  phx-value-user-id={user.id}
                  class="btn btn-primary btn-sm"
                >
                  Chat
                </button>
              </div>
            </div>

            <p :if={@search_query != "" && @search_results == []} class="text-base-content/70 mt-2">
              No users found matching "{@search_query}"
            </p>
          </div>
        </div>

        <div class="space-y-2">
          <div :if={@conversations == []} class="text-center py-12 text-base-content/70">
            <p>No conversations yet.</p>
            <p class="mt-2">Click "New Chat" to start messaging!</p>
          </div>

          <.link
            :for={conv <- @conversations}
            navigate={~p"/chats/#{conv.id}"}
            class="card bg-base-100 shadow hover:shadow-md transition-shadow cursor-pointer block"
          >
            <div class="card-body p-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="avatar placeholder">
                    <div class="bg-primary text-primary-content rounded-full w-12">
                      <span class="text-lg">{get_conversation_initial(conv, @current_user.id)}</span>
                    </div>
                  </div>
                  <div>
                    <h3 class="font-semibold">{get_conversation_name(conv, @current_user.id)}</h3>
                    <p :if={conv.last_message} class="text-sm text-base-content/70 truncate max-w-xs">
                      {conv.last_message.content}
                    </p>
                    <p :if={!conv.last_message} class="text-sm text-base-content/50 italic">
                      No messages yet
                    </p>
                  </div>
                </div>
                <div class="flex flex-col items-end gap-1">
                  <span :if={conv.last_message} class="text-xs text-base-content/50">
                    {format_time(conv.last_message.inserted_at)}
                  </span>
                  <span :if={conv.unread_count > 0} class="badge badge-primary badge-sm">
                    {conv.unread_count}
                  </span>
                </div>
              </div>
            </div>
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp get_conversation_name(%{type: "direct", members: members}, current_user_id) do
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> "Unknown"
      member -> member.user.username
    end
  end

  defp get_conversation_name(%{name: name}, _) when is_binary(name), do: name
  defp get_conversation_name(_, _), do: "Group Chat"

  defp get_conversation_initial(conv, current_user_id) do
    conv
    |> get_conversation_name(current_user_id)
    |> String.first()
    |> String.upcase()
  end

  defp format_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      diff < 604_800 -> "#{div(diff, 86400)}d"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end

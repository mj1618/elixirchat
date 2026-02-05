defmodule ElixirchatWeb.ChatListLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat
  alias Elixirchat.Presence

  @impl true
  def mount(_params, _session, socket) do
    # current_user is already assigned by on_mount hook
    current_user = socket.assigns.current_user
    conversations = Chat.list_user_conversations(current_user.id)
    muted_conversation_ids = Chat.list_muted_conversation_ids(current_user.id)
    archived_count = Chat.get_archived_count(current_user.id)

    # Track presence and subscribe to updates when connected
    online_user_ids =
      if connected?(socket) do
        Presence.track_user(self(), current_user)
        Presence.subscribe()
        Presence.get_online_user_ids()
      else
        []
      end

    scheduled_count = Chat.get_scheduled_message_count(current_user.id)

    {:ok,
     assign(socket,
       conversations: conversations,
       search_query: "",
       search_results: [],
       show_search: false,
       online_user_ids: online_user_ids,
       muted_conversation_ids: muted_conversation_ids,
       view_mode: :active,
       archived_count: archived_count,
       scheduled_count: scheduled_count
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
  def handle_event("show_active", _, socket) do
    conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
    {:noreply, assign(socket, view_mode: :active, conversations: conversations)}
  end

  @impl true
  def handle_event("show_archived", _, socket) do
    archived = Chat.list_archived_conversations(socket.assigns.current_user.id)
    {:noreply, assign(socket, view_mode: :archived, conversations: archived)}
  end

  @impl true
  def handle_event("archive_conversation", %{"id" => conversation_id}, socket) do
    conversation_id = String.to_integer(conversation_id)

    case Chat.archive_conversation(conversation_id, socket.assigns.current_user.id) do
      {:ok, _} ->
        conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
        archived_count = Chat.get_archived_count(socket.assigns.current_user.id)
        {:noreply, assign(socket, conversations: conversations, archived_count: archived_count)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not archive conversation")}
    end
  end

  @impl true
  def handle_event("unarchive_conversation", %{"id" => conversation_id}, socket) do
    conversation_id = String.to_integer(conversation_id)

    case Chat.unarchive_conversation(conversation_id, socket.assigns.current_user.id) do
      {:ok, _} ->
        archived = Chat.list_archived_conversations(socket.assigns.current_user.id)
        archived_count = Chat.get_archived_count(socket.assigns.current_user.id)
        {:noreply, assign(socket, conversations: archived, archived_count: archived_count)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not unarchive conversation")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Update online user IDs when presence changes
    {:noreply, assign(socket, online_user_ids: Presence.get_online_user_ids())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="navbar bg-base-100 shadow-sm">
        <div class="flex-1">
          <.link href="/" class="btn btn-ghost text-xl">Elixirchat</.link>
        </div>
        <div class="flex-none gap-2 items-center flex">
          <ElixirchatWeb.Layouts.theme_toggle />
          <span class="mr-2">Hello, <strong>{@current_user.username}</strong></span>
          <.link navigate={~p"/starred"} class="btn btn-ghost btn-sm" title="Starred Messages">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z" />
            </svg>
          </.link>
          <.link navigate={~p"/scheduled"} class="btn btn-ghost btn-sm indicator" title="Scheduled Messages">
            <span :if={@scheduled_count > 0} class="indicator-item badge badge-info badge-xs">{@scheduled_count}</span>
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
            </svg>
          </.link>
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
          <div class="flex gap-2">
            <button phx-click="toggle_search" class="btn btn-primary btn-sm">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 mr-1">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
              </svg>
              New Chat
            </button>
            <.link navigate={~p"/groups/new"} class="btn btn-secondary btn-sm">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 mr-1">
                <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
              </svg>
              New Group
            </.link>
          </div>
        </div>

        <%!-- Tabs for Active/Archived conversations --%>
        <div class="tabs tabs-boxed mb-4">
          <button
            phx-click="show_active"
            class={["tab", @view_mode == :active && "tab-active"]}
          >
            Chats
          </button>
          <button
            phx-click="show_archived"
            class={["tab", @view_mode == :archived && "tab-active"]}
          >
            Archived
            <span :if={@archived_count > 0} class="badge badge-sm ml-1">{@archived_count}</span>
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
          <div :if={@conversations == [] && @view_mode == :active} class="text-center py-12 text-base-content/70">
            <p>No conversations yet.</p>
            <p class="mt-2">Click "New Chat" to start messaging!</p>
          </div>

          <div :if={@conversations == [] && @view_mode == :archived} class="text-center py-12 text-base-content/70">
            <p>No archived conversations.</p>
            <p class="mt-2">Archive conversations to hide them from your main chat list.</p>
          </div>

          <div
            :for={conv <- @conversations}
            class="card bg-base-100 shadow hover:shadow-md transition-shadow group"
          >
            <div class="card-body p-4">
              <div class="flex items-center justify-between">
                <.link navigate={~p"/chats/#{conv.id}"} class="flex items-center gap-3 flex-1 min-w-0">
                  <div class="avatar avatar-placeholder">
                    <div class={[
                      "rounded-full w-12 h-12 flex items-center justify-center",
                      !get_conversation_avatar(conv, @current_user.id) && (conv.type == "group" && "bg-secondary text-secondary-content" || "bg-primary text-primary-content")
                    ]}>
                      <%= if avatar = get_conversation_avatar(conv, @current_user.id) do %>
                        <img src={"/uploads/avatars/#{avatar}"} alt="Avatar" class="rounded-full w-full h-full object-cover" />
                      <% else %>
                        <span class="text-lg">{get_conversation_initial(conv, @current_user.id)}</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <div class={[
                        "w-2.5 h-2.5 rounded-full flex-shrink-0",
                        is_conversation_online?(conv, @current_user.id, @online_user_ids) && "bg-success" || "bg-base-content/30"
                      ]}></div>
                      <%!-- Pin indicator --%>
                      <span :if={conv.pinned_at} class="text-primary flex-shrink-0" title="Pinned">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 24 24" class="w-4 h-4">
                          <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5.2v6h1.6v-6H18v-2l-2-2z"/>
                        </svg>
                      </span>
                      <h3 class="font-semibold truncate">{get_conversation_name(conv, @current_user.id)}</h3>
                      <%!-- Mute indicator --%>
                      <span :if={conv.id in @muted_conversation_ids} class="text-warning flex-shrink-0" title="Muted">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M17.25 9.75 19.5 12m0 0 2.25 2.25M19.5 12l2.25-2.25M19.5 12l-2.25 2.25m-10.5-6 4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z" />
                        </svg>
                      </span>
                      <span :if={conv.type == "group"} class="badge badge-sm badge-outline flex-shrink-0">
                        {get_group_online_text(conv, @online_user_ids)}
                      </span>
                    </div>
                    <%!-- User status for direct messages --%>
                    <p :if={conv.type == "direct" && get_other_user_status(conv, @current_user.id)} class="text-xs text-base-content/60 truncate max-w-xs">
                      {get_other_user_status(conv, @current_user.id)}
                    </p>
                    <p :if={conv.last_message} class="text-sm text-base-content/70 truncate max-w-xs">
                      <span :if={conv.type == "group"} class="font-medium">{conv.last_message.sender.username}: </span>
                      {conv.last_message.content}
                    </p>
                    <p :if={!conv.last_message} class="text-sm text-base-content/50 italic">
                      No messages yet
                    </p>
                  </div>
                </.link>
                <div class="flex items-center gap-2 flex-shrink-0">
                  <div class="flex flex-col items-end gap-1">
                    <span :if={conv.last_message} class="text-xs text-base-content/50">
                      {format_time(conv.last_message.inserted_at)}
                    </span>
                    <span :if={conv.unread_count > 0} class="badge badge-primary badge-sm">
                      {conv.unread_count}
                    </span>
                  </div>
                  <%!-- Archive/Unarchive button --%>
                  <%= if @view_mode == :active do %>
                    <button
                      phx-click="archive_conversation"
                      phx-value-id={conv.id}
                      class="btn btn-ghost btn-sm btn-circle opacity-0 group-hover:opacity-100 transition-opacity"
                      title="Archive conversation"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m20.25 7.5-.625 10.632a2.25 2.25 0 0 1-2.247 2.118H6.622a2.25 2.25 0 0 1-2.247-2.118L3.75 7.5m8.25 3v6.75m0 0-3-3m3 3 3-3M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125Z" />
                      </svg>
                    </button>
                  <% else %>
                    <button
                      phx-click="unarchive_conversation"
                      phx-value-id={conv.id}
                      class="btn btn-ghost btn-sm btn-circle"
                      title="Unarchive conversation"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m20.25 7.5-.625 10.632a2.25 2.25 0 0 1-2.247 2.118H6.622a2.25 2.25 0 0 1-2.247-2.118L3.75 7.5m8.25 3v6.75m0 0 3-3m-3 3-3-3M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125Z" />
                      </svg>
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
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

  # For direct conversations, returns the other user's avatar filename (if any)
  # For groups, returns nil (groups don't have avatars)
  defp get_conversation_avatar(%{type: "direct", members: members}, current_user_id) do
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> nil
      member -> member.user.avatar_filename
    end
  end

  defp get_conversation_avatar(_, _), do: nil

  defp format_time(datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      diff < 604_800 -> "#{div(diff, 86400)}d"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  # Online presence helpers
  defp is_conversation_online?(%{type: "direct", members: members}, current_user_id, online_user_ids) do
    # For direct chats, check if the other user is online
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> false
      member -> member.user_id in online_user_ids
    end
  end

  defp is_conversation_online?(%{type: "group", members: members}, _current_user_id, online_user_ids) do
    # For group chats, consider online if at least one other member is online
    Enum.any?(members, fn m -> m.user_id in online_user_ids end)
  end

  defp is_conversation_online?(_, _, _), do: false

  defp get_group_online_text(%{members: members}, online_user_ids) do
    total = length(members)
    online = Enum.count(members, fn m -> m.user_id in online_user_ids end)
    "#{online}/#{total} online"
  end

  # Gets the other user's status for direct conversations
  defp get_other_user_status(%{type: "direct", members: members}, current_user_id) do
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> nil
      member -> member.user.status
    end
  end

  defp get_other_user_status(_, _), do: nil
end

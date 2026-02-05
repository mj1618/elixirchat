defmodule ElixirchatWeb.StarredLive do
  @moduledoc """
  LiveView for displaying all starred messages for the current user.
  Messages are grouped by conversation.
  """
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat

  @impl true
  def mount(_params, _session, socket) do
    starred_messages = Chat.list_starred_messages(socket.assigns.current_user.id)

    # Group by conversation
    grouped =
      starred_messages
      |> Enum.group_by(fn s -> s.message.conversation end)
      |> Enum.sort_by(fn {_conv, msgs} ->
        # Sort groups by most recent starred message
        msgs |> Enum.map(& &1.starred_at) |> Enum.max()
      end, {:desc, DateTime})

    {:ok,
     assign(socket,
       starred_messages: starred_messages,
       grouped: grouped
     )}
  end

  @impl true
  def handle_event("unstar", %{"message-id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    Chat.unstar_message(message_id, socket.assigns.current_user.id)

    # Refresh list
    starred_messages = Chat.list_starred_messages(socket.assigns.current_user.id)
    grouped =
      starred_messages
      |> Enum.group_by(fn s -> s.message.conversation end)
      |> Enum.sort_by(fn {_conv, msgs} ->
        msgs |> Enum.map(& &1.starred_at) |> Enum.max()
      end, {:desc, DateTime})

    {:noreply, assign(socket, starred_messages: starred_messages, grouped: grouped)}
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
          <h1 class="text-xl font-bold flex items-center gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-warning">
              <path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z" />
            </svg>
            Starred Messages
          </h1>
        </div>
        <div class="flex-none gap-2 items-center flex">
          <ElixirchatWeb.Layouts.theme_toggle />
          <span class="text-sm text-base-content/70">{@current_user.username}</span>
        </div>
      </div>

      <div class="max-w-2xl mx-auto p-4">
        <div :if={@starred_messages == []} class="text-center py-12 text-base-content/70">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-12 h-12 mx-auto mb-2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z" />
          </svg>
          <p class="font-medium">No starred messages yet</p>
          <p class="text-sm mt-1">Star important messages to find them here later</p>
        </div>

        <div :for={{conversation, messages} <- @grouped} class="mb-6">
          <div class="flex items-center gap-2 mb-3">
            <div class="avatar avatar-placeholder">
              <div class={[
                "rounded-full w-8 h-8 flex items-center justify-center text-sm",
                conversation.type == "group" && "bg-secondary text-secondary-content" || "bg-primary text-primary-content"
              ]}>
                {get_conversation_initial(conversation, @current_user.id)}
              </div>
            </div>
            <h2 class="font-semibold">
              {get_conversation_name(conversation, @current_user.id)}
            </h2>
            <span class="badge badge-sm badge-outline">{length(messages)} starred</span>
          </div>

          <div class="space-y-2">
            <div :for={starred <- messages} class="card bg-base-100 shadow hover:shadow-md transition-shadow">
              <div class="card-body p-4">
                <div class="flex items-start gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 text-sm text-base-content/60 mb-1">
                      <span class="font-medium text-base-content">{starred.message.sender.username}</span>
                      <span class="text-xs">{format_date(starred.message.inserted_at)}</span>
                    </div>
                    <.link
                      navigate={~p"/chats/#{starred.message.conversation_id}"}
                      class="block hover:underline"
                    >
                      <p :if={starred.message.deleted_at} class="text-base-content/50 italic">
                        This message was deleted
                      </p>
                      <p :if={!starred.message.deleted_at} class="line-clamp-3">
                        {starred.message.content}
                      </p>
                    </.link>
                    <div class="text-xs text-base-content/50 mt-2">
                      Starred {format_relative_time(starred.starred_at)}
                    </div>
                  </div>
                  <button
                    phx-click="unstar"
                    phx-value-message-id={starred.message.id}
                    class="btn btn-ghost btn-sm btn-circle text-warning flex-shrink-0"
                    title="Unstar"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z" />
                    </svg>
                  </button>
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

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end

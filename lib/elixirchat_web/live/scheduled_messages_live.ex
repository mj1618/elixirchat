defmodule ElixirchatWeb.ScheduledMessagesLive do
  @moduledoc """
  LiveView for displaying all scheduled messages for the current user.
  Messages are grouped by conversation and can be edited or cancelled.
  """
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat

  @impl true
  def mount(_params, _session, socket) do
    scheduled_messages = Chat.list_user_scheduled_messages(socket.assigns.current_user.id)

    # Group by conversation
    grouped =
      scheduled_messages
      |> Enum.group_by(fn s -> s.conversation end)
      |> Enum.sort_by(fn {_conv, msgs} ->
        # Sort groups by earliest scheduled message
        msgs |> Enum.map(& &1.scheduled_for) |> Enum.min()
      end, {:asc, DateTime})

    {:ok,
     assign(socket,
       scheduled_messages: scheduled_messages,
       grouped: grouped,
       editing_id: nil,
       edit_content: "",
       edit_datetime: ""
     )}
  end

  @impl true
  def handle_event("cancel_scheduled", %{"id" => id}, socket) do
    id = String.to_integer(id)
    
    case Chat.cancel_scheduled_message(id, socket.assigns.current_user.id) do
      {:ok, _} ->
        scheduled_messages = Chat.list_user_scheduled_messages(socket.assigns.current_user.id)
        grouped = group_messages(scheduled_messages)
        {:noreply,
         socket
         |> assign(scheduled_messages: scheduled_messages, grouped: grouped)
         |> put_flash(:info, "Scheduled message cancelled")}

      {:error, :already_sent} ->
        {:noreply, put_flash(socket, :error, "Message was already sent")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel message")}
    end
  end

  @impl true
  def handle_event("start_edit", %{"id" => id}, socket) do
    id = String.to_integer(id)
    msg = Enum.find(socket.assigns.scheduled_messages, & &1.id == id)
    
    if msg do
      edit_datetime = 
        msg.scheduled_for
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:minute)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      {:noreply, assign(socket, editing_id: id, edit_content: msg.content, edit_datetime: edit_datetime)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_id: nil, edit_content: "", edit_datetime: "")}
  end

  @impl true
  def handle_event("save_edit", %{"content" => content, "scheduled_for" => scheduled_for_str}, socket) do
    content = String.trim(content)
    
    if content == "" do
      {:noreply, put_flash(socket, :error, "Message cannot be empty")}
    else
      case NaiveDateTime.from_iso8601(scheduled_for_str <> ":00") do
        {:ok, naive_dt} ->
          scheduled_for = DateTime.from_naive!(naive_dt, "Etc/UTC")
          
          if DateTime.compare(scheduled_for, DateTime.add(DateTime.utc_now(), 60, :second)) == :lt do
            {:noreply, put_flash(socket, :error, "Scheduled time must be at least 1 minute in the future")}
          else
            attrs = %{content: content, scheduled_for: scheduled_for}
            
            case Chat.update_scheduled_message(socket.assigns.editing_id, socket.assigns.current_user.id, attrs) do
              {:ok, _} ->
                scheduled_messages = Chat.list_user_scheduled_messages(socket.assigns.current_user.id)
                grouped = group_messages(scheduled_messages)
                
                {:noreply,
                 socket
                 |> assign(
                   scheduled_messages: scheduled_messages,
                   grouped: grouped,
                   editing_id: nil,
                   edit_content: "",
                   edit_datetime: ""
                 )
                 |> put_flash(:info, "Scheduled message updated")}

              {:error, :already_sent} ->
                {:noreply, put_flash(socket, :error, "Message was already sent")}

              {:error, :not_found} ->
                {:noreply, put_flash(socket, :error, "Message not found")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to update message")}
            end
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Invalid date/time format")}
      end
    end
  end

  defp group_messages(messages) do
    messages
    |> Enum.group_by(fn s -> s.conversation end)
    |> Enum.sort_by(fn {_conv, msgs} ->
      msgs |> Enum.map(& &1.scheduled_for) |> Enum.min()
    end, {:asc, DateTime})
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
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-info">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
            </svg>
            Scheduled Messages
          </h1>
        </div>
        <div class="flex-none gap-2 items-center flex">
          <ElixirchatWeb.Layouts.theme_toggle />
          <span class="text-sm text-base-content/70">{@current_user.username}</span>
        </div>
      </div>

      <div class="max-w-2xl mx-auto p-4">
        <div :if={@scheduled_messages == []} class="text-center py-12 text-base-content/70">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-12 h-12 mx-auto mb-2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
          </svg>
          <p class="font-medium">No scheduled messages</p>
          <p class="text-sm mt-1">Schedule a message to send it at a future time</p>
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
            <span class="badge badge-sm badge-info badge-outline">{length(messages)} scheduled</span>
          </div>

          <div class="space-y-2">
            <div :for={scheduled <- messages} class="card bg-base-100 shadow hover:shadow-md transition-shadow">
              <div class="card-body p-4">
                <%!-- Edit mode --%>
                <div :if={@editing_id == scheduled.id}>
                  <form phx-submit="save_edit" class="space-y-3">
                    <div>
                      <label class="label">
                        <span class="label-text">Message</span>
                      </label>
                      <textarea
                        name="content"
                        class="textarea textarea-bordered w-full"
                        rows="3"
                        required
                      ><%= @edit_content %></textarea>
                    </div>
                    <div>
                      <label class="label">
                        <span class="label-text">Scheduled for</span>
                      </label>
                      <input
                        type="datetime-local"
                        name="scheduled_for"
                        class="input input-bordered w-full"
                        value={@edit_datetime}
                        min={get_min_datetime()}
                        required
                      />
                    </div>
                    <div class="flex justify-end gap-2">
                      <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">Cancel</button>
                      <button type="submit" class="btn btn-primary btn-sm">Save</button>
                    </div>
                  </form>
                </div>

                <%!-- View mode --%>
                <div :if={@editing_id != scheduled.id} class="flex items-start gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 text-sm mb-2">
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 text-info">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                      </svg>
                      <span class="font-medium">{format_schedule_time(scheduled.scheduled_for)}</span>
                      <span class="text-xs text-base-content/50">({time_until(scheduled.scheduled_for)})</span>
                    </div>
                    <.link
                      navigate={~p"/chats/#{scheduled.conversation_id}"}
                      class="block hover:underline"
                    >
                      <p class="line-clamp-3">{scheduled.content}</p>
                    </.link>
                    <div :if={scheduled.reply_to} class="text-xs text-base-content/50 mt-2">
                      Replying to a message
                    </div>
                  </div>
                  <div class="flex gap-1 flex-shrink-0">
                    <button
                      phx-click="start_edit"
                      phx-value-id={scheduled.id}
                      class="btn btn-ghost btn-sm btn-circle"
                      title="Edit"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
                      </svg>
                    </button>
                    <button
                      phx-click="cancel_scheduled"
                      phx-value-id={scheduled.id}
                      class="btn btn-ghost btn-sm btn-circle text-error"
                      title="Cancel"
                      data-confirm="Are you sure you want to cancel this scheduled message?"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
                      </svg>
                    </button>
                  </div>
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

  defp format_schedule_time(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp time_until(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(datetime, now, :second)

    cond do
      diff < 0 -> "sending now..."
      diff < 60 -> "in less than a minute"
      diff < 3600 -> "in #{div(diff, 60)} minutes"
      diff < 86400 -> "in #{div(diff, 3600)} hours"
      true -> "in #{div(diff, 86400)} days"
    end
  end

  defp get_min_datetime do
    DateTime.utc_now()
    |> DateTime.add(60, :second)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:minute)
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)
  end
end

defmodule Elixirchat.Chat.ScheduledMessageWorker do
  @moduledoc """
  GenServer that periodically checks for and sends scheduled messages.
  Runs every 30 seconds to check for messages that are due.
  """

  use GenServer
  require Logger

  alias Elixirchat.Chat

  @check_interval :timer.seconds(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Start checking for scheduled messages
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_scheduled, state) do
    process_due_messages()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_scheduled, @check_interval)
  end

  defp process_due_messages do
    Chat.get_due_scheduled_messages()
    |> Enum.each(fn scheduled_msg ->
      case Chat.send_scheduled_message(scheduled_msg) do
        {:ok, _message} ->
          Logger.info("Sent scheduled message #{scheduled_msg.id}")

        {:error, reason} ->
          Logger.error("Failed to send scheduled message #{scheduled_msg.id}: #{inspect(reason)}")
      end
    end)
  end
end

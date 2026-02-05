defmodule Elixirchat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ElixirchatWeb.Telemetry,
      Elixirchat.Repo,
      {DNSCluster, query: Application.get_env(:elixirchat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Elixirchat.PubSub},
      # Presence tracking for online status
      Elixirchat.Presence,
      # Task supervisor for async operations (e.g., AI agent responses)
      {Task.Supervisor, name: Elixirchat.TaskSupervisor},
      # Start to serve requests, typically the last entry
      ElixirchatWeb.Endpoint,
      # Ensure General conversation exists (runs after Repo is started)
      {Task, fn -> ensure_general_conversation() end}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Elixirchat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Creates the General group conversation if it doesn't exist.
  # This runs as a supervised task after the Repo is started.
  defp ensure_general_conversation do
    # Only run if not in test environment to avoid issues with test isolation
    unless Application.get_env(:elixirchat, :env) == :test do
      Elixirchat.Chat.get_or_create_general_conversation()
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ElixirchatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

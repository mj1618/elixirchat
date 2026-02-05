defmodule Elixirchat.Presence do
  @moduledoc """
  Tracks user online presence across the application.

  Uses Phoenix.Presence for distributed presence tracking with
  automatic cleanup when users disconnect.
  """
  use Phoenix.Presence,
    otp_app: :elixirchat,
    pubsub_server: Elixirchat.PubSub

  @presence_topic "users:online"

  @doc """
  Track a user's presence.
  """
  def track_user(pid, user) do
    track(pid, @presence_topic, user.id, %{
      user_id: user.id,
      username: user.username,
      joined_at: DateTime.utc_now()
    })
  end

  @doc """
  Subscribe to presence updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Elixirchat.PubSub, @presence_topic)
  end

  @doc """
  Get list of all online user IDs.
  """
  def get_online_user_ids do
    @presence_topic
    |> list()
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
  end

  @doc """
  Check if a specific user is online.
  """
  def is_user_online?(user_id) do
    @presence_topic
    |> list()
    |> Map.has_key?(to_string(user_id))
  end

  @doc """
  Get count of online users from a list of user IDs.
  """
  def get_online_count(user_ids) when is_list(user_ids) do
    online_ids = get_online_user_ids()

    user_ids
    |> Enum.count(fn id -> id in online_ids end)
  end

  @doc """
  Get the other user in a direct chat.
  """
  def get_other_user_id(members, current_user_id) do
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> nil
      member -> member.user_id
    end
  end
end

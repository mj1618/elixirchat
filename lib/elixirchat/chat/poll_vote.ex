defmodule Elixirchat.Chat.PollVote do
  @moduledoc """
  Schema for poll votes.
  Tracks which user voted for which option in a poll.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User
  alias Elixirchat.Chat.{Poll, PollOption}

  schema "poll_votes" do
    belongs_to :poll, Poll
    belongs_to :poll_option, PollOption
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:poll_id, :poll_option_id, :user_id])
    |> validate_required([:poll_id, :poll_option_id, :user_id])
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:poll_option_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:poll_id, :user_id, :poll_option_id],
      name: :poll_votes_poll_id_user_id_poll_option_id_index,
      message: "already voted for this option"
    )
  end
end

defmodule Elixirchat.Chat.PollOption do
  @moduledoc """
  Schema for poll options.
  Each poll has 2-10 options that users can vote on.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Poll, PollVote}

  schema "poll_options" do
    field :text, :string
    field :position, :integer, default: 0

    belongs_to :poll, Poll
    has_many :votes, PollVote, on_delete: :delete_all

    # Virtual fields for computed results
    field :vote_count, :integer, virtual: true, default: 0
    field :percentage, :integer, virtual: true, default: 0
    field :voter_ids, {:array, :integer}, virtual: true, default: []

    timestamps()
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :position, :poll_id])
    |> validate_required([:text, :poll_id])
    |> validate_length(:text, min: 1, max: 200)
    |> foreign_key_constraint(:poll_id)
  end
end

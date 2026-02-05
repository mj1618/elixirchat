defmodule Elixirchat.Chat.Poll do
  @moduledoc """
  Schema for polls in conversations.
  Polls allow users to create multiple-choice questions that other members can vote on.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User
  alias Elixirchat.Chat.{Conversation, PollOption, PollVote}

  schema "polls" do
    field :question, :string
    field :closed_at, :utc_datetime
    field :allow_multiple, :boolean, default: false
    field :anonymous, :boolean, default: false

    belongs_to :conversation, Conversation
    belongs_to :creator, User
    has_many :options, PollOption, on_delete: :delete_all
    has_many :votes, PollVote, on_delete: :delete_all

    # Virtual fields for computed results
    field :total_votes, :integer, virtual: true, default: 0

    timestamps()
  end

  @doc false
  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [:question, :conversation_id, :creator_id, :allow_multiple, :anonymous, :closed_at])
    |> validate_required([:question, :conversation_id, :creator_id])
    |> validate_length(:question, min: 1, max: 500)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:creator_id)
  end

  @doc """
  Changeset for closing a poll.
  """
  def close_changeset(poll, attrs) do
    poll
    |> cast(attrs, [:closed_at])
  end
end

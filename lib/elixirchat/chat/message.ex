defmodule Elixirchat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Conversation, Reaction}
  alias Elixirchat.Accounts.User

  schema "messages" do
    field :content, :string
    field :edited_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :conversation, Conversation
    belongs_to :sender, User, foreign_key: :sender_id
    belongs_to :reply_to, __MODULE__
    has_many :reactions, Reaction

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :conversation_id, :sender_id, :reply_to_id])
    |> validate_required([:content, :conversation_id, :sender_id])
    |> validate_length(:content, min: 1, max: 5000)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:reply_to_id)
  end

  @doc """
  Changeset for editing a message's content.
  """
  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :edited_at])
    |> validate_required([:content, :edited_at])
    |> validate_length(:content, min: 1, max: 5000)
  end

  @doc """
  Changeset for soft deleting a message.
  """
  def delete_changeset(message, attrs) do
    message
    |> cast(attrs, [:deleted_at])
    |> validate_required([:deleted_at])
  end
end

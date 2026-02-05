defmodule Elixirchat.Chat.Reaction do
  @moduledoc """
  Schema for message reactions (emoji reactions on messages).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Message
  alias Elixirchat.Accounts.User

  @allowed_emojis ~w(👍 👎 ❤️ 😂 😮 😢)

  schema "reactions" do
    field :emoji, :string

    belongs_to :message, Message
    belongs_to :user, User

    timestamps()
  end

  @doc """
  Returns the list of allowed emoji reactions.
  """
  def allowed_emojis, do: @allowed_emojis

  @doc """
  Creates a changeset for a reaction.
  """
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :message_id, :user_id])
    |> validate_required([:emoji, :message_id, :user_id])
    |> validate_inclusion(:emoji, @allowed_emojis, message: "is not a valid emoji")
    |> unique_constraint([:message_id, :user_id, :emoji],
      name: :reactions_message_id_user_id_emoji_index,
      message: "you already reacted with this emoji"
    )
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
  end
end

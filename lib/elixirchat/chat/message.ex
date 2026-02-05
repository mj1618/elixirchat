defmodule Elixirchat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Conversation
  alias Elixirchat.Accounts.User

  schema "messages" do
    field :content, :string

    belongs_to :conversation, Conversation
    belongs_to :sender, User, foreign_key: :sender_id

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :conversation_id, :sender_id])
    |> validate_required([:content, :conversation_id, :sender_id])
    |> validate_length(:content, min: 1, max: 5000)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
  end
end

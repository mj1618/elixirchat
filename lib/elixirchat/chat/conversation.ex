defmodule Elixirchat.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{ConversationMember, Message}

  schema "conversations" do
    field :type, :string, default: "direct"
    field :name, :string

    has_many :members, ConversationMember
    has_many :users, through: [:members, :user]
    has_many :messages, Message

    timestamps()
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:type, :name])
    |> validate_required([:type])
    |> validate_inclusion(:type, ["direct", "group"])
  end
end

defmodule Elixirchat.Chat.PinnedMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Message, Conversation}
  alias Elixirchat.Accounts.User

  @max_pins_per_conversation 5

  schema "pinned_messages" do
    field :pinned_at, :utc_datetime

    belongs_to :message, Message
    belongs_to :conversation, Conversation
    belongs_to :pinned_by, User

    timestamps()
  end

  def changeset(pinned_message, attrs) do
    pinned_message
    |> cast(attrs, [:pinned_at, :message_id, :conversation_id, :pinned_by_id])
    |> validate_required([:pinned_at, :message_id, :conversation_id, :pinned_by_id])
    |> unique_constraint(:message_id, message: "message is already pinned")
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:pinned_by_id)
  end

  def max_pins_per_conversation, do: @max_pins_per_conversation
end

defmodule Elixirchat.Chat.ReadReceipt do
  @moduledoc """
  Schema for tracking when users have read messages in a conversation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Message
  alias Elixirchat.Accounts.User

  schema "read_receipts" do
    field :read_at, :utc_datetime

    belongs_to :message, Message
    belongs_to :user, User

    timestamps()
  end

  @doc """
  Creates a changeset for a read receipt.
  """
  def changeset(read_receipt, attrs) do
    read_receipt
    |> cast(attrs, [:read_at, :message_id, :user_id])
    |> validate_required([:read_at, :message_id, :user_id])
    |> unique_constraint([:message_id, :user_id],
      name: :read_receipts_message_id_user_id_index,
      message: "already read"
    )
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
  end
end

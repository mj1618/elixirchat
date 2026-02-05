defmodule Elixirchat.Accounts.BlockedUser do
  @moduledoc """
  Schema for tracking blocked users.
  When a user blocks another user:
  - The blocked user cannot send direct messages to the blocker
  - The blocked user cannot initiate new conversations with the blocker
  - Blocking is one-directional (A blocking B doesn't mean B blocks A)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User

  schema "blocked_users" do
    field :blocked_at, :utc_datetime

    belongs_to :blocker, User
    belongs_to :blocked, User

    timestamps()
  end

  @doc """
  Creates a changeset for blocking a user.
  """
  def changeset(blocked_user, attrs) do
    blocked_user
    |> cast(attrs, [:blocked_at, :blocker_id, :blocked_id])
    |> validate_required([:blocked_at, :blocker_id, :blocked_id])
    |> validate_not_self_block()
    |> unique_constraint([:blocker_id, :blocked_id], message: "user already blocked")
    |> foreign_key_constraint(:blocker_id)
    |> foreign_key_constraint(:blocked_id)
  end

  defp validate_not_self_block(changeset) do
    blocker_id = get_field(changeset, :blocker_id)
    blocked_id = get_field(changeset, :blocked_id)

    if blocker_id && blocked_id && blocker_id == blocked_id do
      add_error(changeset, :blocked_id, "cannot block yourself")
    else
      changeset
    end
  end
end

defmodule Elixirchat.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password, :string, virtual: true
    field :current_password, :string, virtual: true
    field :password_hash, :string
    field :avatar_filename, :string
    field :status, :string
    field :status_updated_at, :utc_datetime

    timestamps()
  end

  @doc """
  Changeset for user registration.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password])
    |> validate_required([:username, :password])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/, message: "only letters, numbers, and underscores allowed")
    |> validate_length(:password, min: 6, max: 100)
    |> unique_constraint(:username)
    |> hash_password()
  end

  @doc """
  Changeset for changing password.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 6, max: 100)
    |> hash_password()
  end

  defp hash_password(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
      _ ->
        changeset
    end
  end

  @doc """
  Changeset for updating avatar.
  """
  def avatar_changeset(user, attrs) do
    user
    |> cast(attrs, [:avatar_filename])
  end

  @doc """
  Changeset for updating user status.
  """
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status, :status_updated_at])
    |> validate_length(:status, max: 100)
  end
end

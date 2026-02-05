defmodule Elixirchat.Accounts do
  @moduledoc """
  The Accounts context.
  """

  alias Elixirchat.Repo
  alias Elixirchat.Accounts.User

  @doc """
  Creates a user with the given attributes.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a user by id.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @doc """
  Gets a user by id.
  """
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Authenticates a user by username and password.
  """
  def authenticate_user(username, password) do
    user = get_user_by_username(username)

    cond do
      user && Bcrypt.verify_pass(password, user.password_hash) ->
        {:ok, user}
      user ->
        {:error, :invalid_password}
      true ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :not_found}
    end
  end

  @doc """
  Returns a changeset for tracking user changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  @doc """
  Returns a changeset for changing user password.
  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs)
  end

  @doc """
  Validates that the current password is correct.
  """
  def validate_current_password(%User{} = user, password) do
    if Bcrypt.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      {:error, :invalid_password}
    end
  end

  @doc """
  Updates the user's password.
  Requires valid current password for verification.
  """
  def update_user_password(%User{} = user, current_password, attrs) do
    case validate_current_password(user, current_password) do
      {:ok, _user} ->
        user
        |> User.password_changeset(attrs)
        |> Repo.update()

      {:error, :invalid_password} ->
        {:error, :invalid_current_password}
    end
  end

  @doc """
  Deletes a user account.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end
end

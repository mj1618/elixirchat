defmodule Elixirchat.Accounts do
  @moduledoc """
  The Accounts context.
  """

  alias Elixirchat.Repo
  alias Elixirchat.Accounts.User

  @doc """
  Creates a user with the given attributes.
  Automatically adds the user to the General group conversation.
  """
  def create_user(attrs \\ %{}) do
    result =
      %User{}
      |> User.registration_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, user} ->
        # Add the new user to the General group
        Elixirchat.Chat.add_user_to_general(user.id)
        {:ok, user}

      error ->
        error
    end
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
    # Delete avatar file if exists
    if user.avatar_filename do
      delete_avatar_file(user.avatar_filename)
    end

    Repo.delete(user)
  end

  # ===============================
  # Avatar Functions
  # ===============================

  @doc """
  Returns the path to the avatars directory.
  Creates the directory if it doesn't exist.
  """
  def avatars_dir do
    dir = Path.join([:code.priv_dir(:elixirchat), "static", "uploads", "avatars"])
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Updates the user's avatar.
  """
  def update_user_avatar(%User{} = user, attrs) do
    # Delete old avatar file if it exists and we're uploading a new one
    if user.avatar_filename && attrs[:avatar_filename] do
      delete_avatar_file(user.avatar_filename)
    end

    user
    |> User.avatar_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Removes the user's avatar.
  """
  def delete_user_avatar(%User{} = user) do
    if user.avatar_filename do
      delete_avatar_file(user.avatar_filename)
    end

    user
    |> User.avatar_changeset(%{avatar_filename: nil})
    |> Repo.update()
  end

  defp delete_avatar_file(filename) do
    path = Path.join(avatars_dir(), filename)

    if File.exists?(path) do
      File.rm(path)
    end
  end

  @doc """
  Returns the URL path to a user's avatar, or nil if no avatar.
  """
  def avatar_url(%User{avatar_filename: nil}), do: nil
  def avatar_url(%User{avatar_filename: filename}), do: "/uploads/avatars/#{filename}"

  @doc """
  Checks if a user has an avatar uploaded.
  """
  def has_avatar?(%User{avatar_filename: nil}), do: false
  def has_avatar?(%User{avatar_filename: _}), do: true
end

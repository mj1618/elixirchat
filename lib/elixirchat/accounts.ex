defmodule Elixirchat.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias Elixirchat.Repo
  alias Elixirchat.Accounts.{User, BlockedUser}

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

  # ===============================
  # Status Functions
  # ===============================

  @doc """
  Updates the user's status.
  Empty or whitespace-only status is treated as clearing the status.
  """
  def update_user_status(%User{} = user, status) when is_binary(status) do
    status = String.trim(status)
    status = if status == "", do: nil, else: status

    result =
      user
      |> User.status_changeset(%{
        status: status,
        status_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    case result do
      {:ok, updated_user} ->
        broadcast_status_change(updated_user)
        {:ok, updated_user}

      error ->
        error
    end
  end

  def update_user_status(%User{} = user, nil) do
    clear_user_status(user)
  end

  @doc """
  Clears the user's status.
  """
  def clear_user_status(%User{} = user) do
    result =
      user
      |> User.status_changeset(%{status: nil, status_updated_at: nil})
      |> Repo.update()

    case result do
      {:ok, updated_user} ->
        broadcast_status_change(updated_user)
        {:ok, updated_user}

      error ->
        error
    end
  end

  @doc """
  Returns a list of preset status options.
  """
  def preset_statuses do
    [
      %{emoji: "🟢", text: "Available"},
      %{emoji: "💼", text: "In a meeting"},
      %{emoji: "🏠", text: "Working from home"},
      %{emoji: "🚫", text: "Do not disturb"},
      %{emoji: "🌴", text: "On vacation"},
      %{emoji: "🍔", text: "Out to lunch"},
      %{emoji: "😷", text: "Out sick"},
      %{emoji: "🚗", text: "Commuting"}
    ]
  end

  defp broadcast_status_change(user) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "user:#{user.id}:status",
      {:status_changed, user.id, user.status}
    )
  end

  @doc """
  Subscribe to status changes for a specific user.
  """
  def subscribe_to_user_status(user_id) do
    Phoenix.PubSub.subscribe(Elixirchat.PubSub, "user:#{user_id}:status")
  end

  # ===============================
  # Block User Functions
  # ===============================

  @doc """
  Blocks a user. The blocker_id is the user doing the blocking, blocked_id is the user being blocked.
  Returns {:ok, blocked_user} or {:error, changeset}.
  """
  def block_user(blocker_id, blocked_id) do
    %BlockedUser{}
    |> BlockedUser.changeset(%{
      blocker_id: blocker_id,
      blocked_id: blocked_id,
      blocked_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  @doc """
  Unblocks a user.
  Returns :ok whether or not the user was previously blocked.
  """
  def unblock_user(blocker_id, blocked_id) do
    from(b in BlockedUser,
      where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Checks if blocker_id has blocked blocked_id.
  Returns true if blocked, false otherwise.
  """
  def is_blocked?(blocker_id, blocked_id) do
    from(b in BlockedUser,
      where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
    )
    |> Repo.exists?()
  end

  @doc """
  Checks if user_id is blocked by other_id.
  This is the reverse perspective - has the other person blocked me?
  """
  def is_blocked_by?(user_id, other_id) do
    is_blocked?(other_id, user_id)
  end

  @doc """
  Lists all users blocked by the given user.
  Returns a list of BlockedUser structs with the blocked user preloaded.
  """
  def list_blocked_users(user_id) do
    from(b in BlockedUser,
      where: b.blocker_id == ^user_id,
      join: u in assoc(b, :blocked),
      preload: [blocked: u],
      order_by: [desc: b.blocked_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets blocked user IDs for a user as a MapSet for fast lookup.
  """
  def get_blocked_user_ids(user_id) do
    from(b in BlockedUser,
      where: b.blocker_id == ^user_id,
      select: b.blocked_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Gets user IDs that have blocked the given user (blockers of this user).
  Useful for checking if someone has blocked you.
  """
  def get_blocker_ids(user_id) do
    from(b in BlockedUser,
      where: b.blocked_id == ^user_id,
      select: b.blocker_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Checks if there's a block relationship in either direction between two users.
  Returns :ok if no blocks, or {:error, :user_blocked | :blocked_by_user}.
  """
  def check_block_status(user1_id, user2_id) do
    cond do
      is_blocked?(user1_id, user2_id) ->
        {:error, :user_blocked}

      is_blocked_by?(user1_id, user2_id) ->
        {:error, :blocked_by_user}

      true ->
        :ok
    end
  end
end

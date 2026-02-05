defmodule Elixirchat.Accounts.UserTest do
  use Elixirchat.DataCase, async: true

  alias Elixirchat.Accounts.User

  describe "registration_changeset/2" do
    test "validates required fields" do
      changeset = User.registration_changeset(%User{}, %{})
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).username
      assert "can't be blank" in errors_on(changeset).password
    end

    test "validates username minimum length" do
      changeset = User.registration_changeset(%User{}, %{username: "ab", password: "password123"})
      assert changeset.valid? == false
      assert "should be at least 3 character(s)" in errors_on(changeset).username
    end

    test "validates username maximum length" do
      long_username = String.duplicate("a", 31)
      changeset = User.registration_changeset(%User{}, %{username: long_username, password: "password123"})
      assert changeset.valid? == false
      assert "should be at most 30 character(s)" in errors_on(changeset).username
    end

    test "validates username format allows alphanumeric and underscores" do
      valid_usernames = ["user123", "test_user", "USER_123", "a1b2c3"]

      for username <- valid_usernames do
        changeset = User.registration_changeset(%User{}, %{username: username, password: "password123"})
        assert changeset.valid? == true, "Expected #{username} to be valid"
      end
    end

    test "validates username format rejects special characters" do
      invalid_usernames = ["user@name", "user.name", "user-name", "user name", "user!name", "user#name"]

      for username <- invalid_usernames do
        changeset = User.registration_changeset(%User{}, %{username: username, password: "password123"})
        assert changeset.valid? == false, "Expected #{username} to be invalid"
        assert "only letters, numbers, and underscores allowed" in errors_on(changeset).username
      end
    end

    test "validates password minimum length" do
      changeset = User.registration_changeset(%User{}, %{username: "testuser", password: "12345"})
      assert changeset.valid? == false
      assert "should be at least 6 character(s)" in errors_on(changeset).password
    end

    test "validates password maximum length" do
      long_password = String.duplicate("a", 101)
      changeset = User.registration_changeset(%User{}, %{username: "testuser", password: long_password})
      assert changeset.valid? == false
      assert "should be at most 100 character(s)" in errors_on(changeset).password
    end

    test "hashes password on valid changeset" do
      changeset = User.registration_changeset(%User{}, %{username: "testuser", password: "password123"})
      assert changeset.valid? == true
      password_hash = get_change(changeset, :password_hash)
      assert password_hash != nil
      assert password_hash != "password123"
      # Bcrypt hashes start with $2b$
      assert String.starts_with?(password_hash, "$2b$")
    end

    test "does not hash password on invalid changeset" do
      changeset = User.registration_changeset(%User{}, %{username: "ab", password: "password123"})
      assert changeset.valid? == false
      # Password hash should not be set when changeset is invalid
      assert get_change(changeset, :password_hash) == nil
    end

    test "password is stored as virtual field" do
      changeset = User.registration_changeset(%User{}, %{username: "testuser", password: "password123"})
      assert get_change(changeset, :password) == "password123"
    end

    test "sets unique constraint on username" do
      # First, create a user
      {:ok, _user} =
        %User{}
        |> User.registration_changeset(%{username: "unique_user", password: "password123"})
        |> Elixirchat.Repo.insert()

      # Try to create another user with the same username
      {:error, changeset} =
        %User{}
        |> User.registration_changeset(%{username: "unique_user", password: "differentpassword"})
        |> Elixirchat.Repo.insert()

      assert "has already been taken" in errors_on(changeset).username
    end

    test "accepts valid attributes" do
      attrs = %{username: "valid_user", password: "valid_password123"}
      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.valid? == true
    end

    test "accepts boundary length values" do
      # Minimum username length (3 chars)
      changeset = User.registration_changeset(%User{}, %{username: "abc", password: "password123"})
      assert changeset.valid? == true

      # Maximum username length (30 chars)
      changeset = User.registration_changeset(%User{}, %{username: String.duplicate("a", 30), password: "password123"})
      assert changeset.valid? == true

      # Minimum password length (6 chars)
      changeset = User.registration_changeset(%User{}, %{username: "testuser", password: "123456"})
      assert changeset.valid? == true

      # Maximum password length (100 chars)
      changeset = User.registration_changeset(%User{}, %{username: "testuser2", password: String.duplicate("a", 100)})
      assert changeset.valid? == true
    end
  end

  describe "schema" do
    test "has expected fields" do
      user = %User{}
      assert Map.has_key?(user, :username)
      assert Map.has_key?(user, :password)
      assert Map.has_key?(user, :password_hash)
      assert Map.has_key?(user, :inserted_at)
      assert Map.has_key?(user, :updated_at)
    end

    test "password field is virtual" do
      # Create a user in the database
      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{username: "schema_test_user", password: "password123"})
        |> Elixirchat.Repo.insert()

      # Fetch the user from the database
      fetched_user = Elixirchat.Repo.get!(User, user.id)

      # Virtual field should be nil when fetched from DB
      assert fetched_user.password == nil
      # But password_hash should be persisted
      assert fetched_user.password_hash != nil
    end
  end
end

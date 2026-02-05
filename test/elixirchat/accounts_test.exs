defmodule Elixirchat.AccountsTest do
  use Elixirchat.DataCase, async: true

  alias Elixirchat.Accounts
  alias Elixirchat.Accounts.User

  import Elixirchat.Fixtures

  describe "create_user/1" do
    test "creates a user with valid attributes" do
      attrs = %{username: "testuser", password: "password123"}
      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.username == "testuser"
      assert user.password_hash != nil
      # Password should not be stored in plain text
      assert user.password_hash != "password123"
    end

    test "fails with missing username" do
      attrs = %{password: "password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "can't be blank" in errors_on(changeset).username
    end

    test "fails with missing password" do
      attrs = %{username: "testuser"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "can't be blank" in errors_on(changeset).password
    end

    test "fails with username shorter than 3 characters" do
      attrs = %{username: "ab", password: "password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "should be at least 3 character(s)" in errors_on(changeset).username
    end

    test "fails with username longer than 30 characters" do
      long_username = String.duplicate("a", 31)
      attrs = %{username: long_username, password: "password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "should be at most 30 character(s)" in errors_on(changeset).username
    end

    test "fails with invalid username characters" do
      attrs = %{username: "test user!", password: "password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "only letters, numbers, and underscores allowed" in errors_on(changeset).username
    end

    test "fails with password shorter than 6 characters" do
      attrs = %{username: "testuser", password: "12345"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "should be at least 6 character(s)" in errors_on(changeset).password
    end

    test "fails with duplicate username" do
      user_fixture(%{username: "existinguser"})
      attrs = %{username: "existinguser", password: "password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "has already been taken" in errors_on(changeset).username
    end

    test "hashes the password" do
      attrs = %{username: "testuser", password: "password123"}
      {:ok, user} = Accounts.create_user(attrs)
      assert Bcrypt.verify_pass("password123", user.password_hash)
    end
  end

  describe "get_user_by_username/1" do
    test "returns user when exists" do
      user = user_fixture(%{username: "findme"})
      found_user = Accounts.get_user_by_username("findme")
      assert found_user.id == user.id
    end

    test "returns nil when user does not exist" do
      assert Accounts.get_user_by_username("nonexistent") == nil
    end
  end

  describe "get_user!/1" do
    test "returns user when exists" do
      user = user_fixture()
      found_user = Accounts.get_user!(user.id)
      assert found_user.id == user.id
    end

    test "raises when user does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(999_999)
      end
    end
  end

  describe "get_user/1" do
    test "returns user when exists" do
      user = user_fixture()
      found_user = Accounts.get_user(user.id)
      assert found_user.id == user.id
    end

    test "returns nil when user does not exist" do
      assert Accounts.get_user(999_999) == nil
    end
  end

  describe "authenticate_user/2" do
    test "returns user with valid credentials" do
      user_fixture(%{username: "authuser", password: "correctpass"})
      assert {:ok, user} = Accounts.authenticate_user("authuser", "correctpass")
      assert user.username == "authuser"
    end

    test "returns error with invalid password" do
      user_fixture(%{username: "authuser", password: "correctpass"})
      assert {:error, :invalid_password} = Accounts.authenticate_user("authuser", "wrongpass")
    end

    test "returns error when user does not exist" do
      assert {:error, :not_found} = Accounts.authenticate_user("nonexistent", "anypass")
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      changeset = Accounts.change_user_registration(%User{})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset with changes when attrs provided" do
      changeset = Accounts.change_user_registration(%User{}, %{username: "newuser"})
      assert changeset.changes[:username] == "newuser"
    end
  end
end

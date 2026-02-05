defmodule Elixirchat.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Elixirchat.Accounts` context.
  """

  @doc """
  Generate a unique username.
  """
  def unique_username, do: "user#{System.unique_integer([:positive])}"

  @doc """
  Generate a user with optional attribute overrides.

  ## Examples

      iex> user_fixture()
      %Elixirchat.Accounts.User{}

      iex> user_fixture(%{username: "custom_user"})
      %Elixirchat.Accounts.User{username: "custom_user"}

  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        username: unique_username(),
        password: "valid_password123"
      })
      |> Elixirchat.Accounts.create_user()

    user
  end

  @doc """
  Returns valid user attributes for testing.
  """
  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      username: unique_username(),
      password: "valid_password123"
    })
  end
end

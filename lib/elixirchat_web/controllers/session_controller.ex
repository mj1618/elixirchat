defmodule ElixirchatWeb.SessionController do
  use ElixirchatWeb, :controller

  alias Elixirchat.Accounts
  alias ElixirchatWeb.Plugs.Auth

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        conn
        |> Auth.log_in_user(user)
        |> put_flash(:info, "Welcome back, #{user.username}!")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid username or password")
        |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> Auth.log_out_user()
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: ~p"/")
  end
end

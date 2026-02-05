defmodule ElixirchatWeb.Plugs.Auth do
  @moduledoc """
  Authentication plug for handling user sessions.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Elixirchat.Accounts

  def init(opts), do: opts

  @doc """
  Fetches the current user from the session and assigns it to the connection.
  """
  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end

  @doc """
  Logs in the user by storing the user id in the session.
  """
  def log_in_user(conn, user) do
    conn
    |> put_session(:user_id, user.id)
    |> configure_session(renew: true)
  end

  @doc """
  Logs out the user by clearing the session.
  """
  def log_out_user(conn) do
    conn
    |> configure_session(drop: true)
  end

  @doc """
  Plug that requires authentication.
  Redirects to login page if user is not authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Plug that redirects authenticated users.
  Useful for login/signup pages.
  """
  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end
end

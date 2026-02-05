defmodule ElixirchatWeb.PageController do
  use ElixirchatWeb, :controller

  def home(conn, _params) do
    render(conn, :home, current_user: conn.assigns[:current_user])
  end
end

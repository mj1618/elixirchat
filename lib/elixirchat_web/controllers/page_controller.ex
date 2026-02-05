defmodule ElixirchatWeb.PageController do
  use ElixirchatWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

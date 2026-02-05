defmodule ElixirchatWeb.ChatListLiveTest do
  use ElixirchatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Elixirchat.Fixtures

  alias Elixirchat.Chat

  describe "ChatListLive" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, redirect}} = live(conn, ~p"/chats")
      assert redirect.to == "/login"
    end

    test "renders chat list for authenticated user", %{conn: conn} do
      user = user_fixture(%{username: "chatuser"})
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/chats")

      assert html =~ "Chats"
      assert html =~ "chatuser"
      assert html =~ "New Chat"
      assert has_element?(view, "button", "New Chat")
    end

    test "shows empty state when no conversations", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/chats")

      assert html =~ "No conversations yet"
    end

    test "shows conversations", %{conn: conn} do
      user1 = user_fixture(%{username: "alice"})
      user2 = user_fixture(%{username: "bob"})
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)
      Chat.send_message(conversation.id, user2.id, "Hello Alice!")

      conn = log_in_user(conn, user1)
      {:ok, _view, html} = live(conn, ~p"/chats")

      assert html =~ "bob"
      assert html =~ "Hello Alice!"
    end

    test "shows search when clicking new chat", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/chats")

      html = view |> element("button", "New Chat") |> render_click()

      assert html =~ "Find a user to chat with"
      assert has_element?(view, ~s|input[name="query"]|)
    end

    test "searches for users", %{conn: conn} do
      user1 = user_fixture(%{username: "searcher"})
      _user2 = user_fixture(%{username: "findme"})
      conn = log_in_user(conn, user1)

      {:ok, view, _html} = live(conn, ~p"/chats")

      # Open search
      view |> element("button", "New Chat") |> render_click()

      # Search for user
      html = view |> form("form", query: "findme") |> render_change()

      assert html =~ "findme"
      assert has_element?(view, "button", "Chat")
    end

    test "starts chat with selected user", %{conn: conn} do
      user1 = user_fixture(%{username: "searcher"})
      user2 = user_fixture(%{username: "target"})
      conn = log_in_user(conn, user1)

      {:ok, view, _html} = live(conn, ~p"/chats")

      # Open search and find user
      view |> element("button", "New Chat") |> render_click()
      view |> form("form", query: "target") |> render_change()

      # Start chat - use quoted attribute value for valid CSS selector
      view |> element(~s|button[phx-click="start_chat"][phx-value-user-id="#{user2.id}"]|) |> render_click()

      # Should redirect to the chat
      {path, _} = assert_redirect(view)
      assert path =~ "/chats/"
    end

    test "shows unread count badge", %{conn: conn} do
      user1 = user_fixture(%{username: "alice"})
      user2 = user_fixture(%{username: "bob"})
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)
      Chat.send_message(conversation.id, user2.id, "Message 1")
      Chat.send_message(conversation.id, user2.id, "Message 2")

      conn = log_in_user(conn, user1)
      {:ok, _view, html} = live(conn, ~p"/chats")

      assert html =~ "2"
    end
  end

  # Helper to log in a user
  defp log_in_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:user_id, user.id)
  end
end

defmodule ElixirchatWeb.ChatLiveTest do
  use ElixirchatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Elixirchat.Fixtures

  alias Elixirchat.Chat

  describe "ChatLive" do
    test "redirects to login when not authenticated", %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      {:error, {:redirect, redirect}} = live(conn, ~p"/chats/#{conversation.id}")
      assert redirect.to == "/login"
    end

    test "redirects when user is not a member", %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conn = log_in_user(conn, user3)
      # The redirect happens immediately since user is not a member
      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/chats/#{conversation.id}")

      assert path == "/chats"
      assert flash["error"] =~ "Access denied"
    end

    test "renders chat for member", %{conn: conn} do
      user1 = user_fixture(%{username: "alice"})
      user2 = user_fixture(%{username: "bob"})
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conn = log_in_user(conn, user1)
      {:ok, view, html} = live(conn, ~p"/chats/#{conversation.id}")

      assert html =~ "bob"
      assert html =~ "alice"
      assert has_element?(view, "form")
      assert has_element?(view, ~s|input[name="message"]|)
    end

    test "shows messages", %{conn: conn} do
      user1 = user_fixture(%{username: "alice"})
      user2 = user_fixture(%{username: "bob"})
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)
      Chat.send_message(conversation.id, user1.id, "Hello from Alice!")
      Chat.send_message(conversation.id, user2.id, "Hi Alice!")

      conn = log_in_user(conn, user1)
      {:ok, _view, html} = live(conn, ~p"/chats/#{conversation.id}")

      assert html =~ "Hello from Alice!"
      assert html =~ "Hi Alice!"
    end

    test "shows empty state when no messages", %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conn = log_in_user(conn, user1)
      {:ok, _view, html} = live(conn, ~p"/chats/#{conversation.id}")

      assert html =~ "No messages yet"
    end

    test "sends a message", %{conn: conn} do
      user1 = user_fixture(%{username: "alice"})
      user2 = user_fixture(%{username: "bob"})
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conn = log_in_user(conn, user1)
      {:ok, view, _html} = live(conn, ~p"/chats/#{conversation.id}")

      view
      |> form("form", message: "Hello World!")
      |> render_submit()

      # The message is sent via PubSub, so we need to render again to see it
      # Wait a bit for the PubSub message to arrive
      Process.sleep(50)
      html = render(view)

      assert html =~ "Hello World!"
    end

    test "does not send empty message", %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conn = log_in_user(conn, user1)
      {:ok, view, _html} = live(conn, ~p"/chats/#{conversation.id}")

      html =
        view
        |> form("form", message: "   ")
        |> render_submit()

      # Should still show empty state since whitespace-only messages are not sent
      assert html =~ "No messages yet"
    end

    test "receives real-time messages", %{conn: conn} do
      user1 = user_fixture(%{username: "alice"})
      user2 = user_fixture(%{username: "bob"})
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conn = log_in_user(conn, user1)
      {:ok, view, _html} = live(conn, ~p"/chats/#{conversation.id}")

      # Simulate another user sending a message (broadcasts to subscribers)
      Chat.send_message(conversation.id, user2.id, "Hi from Bob!")

      # The view should receive the message via PubSub
      html = render(view)
      assert html =~ "Hi from Bob!"
    end

    test "has back button to chat list", %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conn = log_in_user(conn, user1)
      {:ok, view, _html} = live(conn, ~p"/chats/#{conversation.id}")

      assert has_element?(view, ~s|a[href="/chats"]|)
    end
  end

  # Helper to log in a user
  defp log_in_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:user_id, user.id)
  end
end

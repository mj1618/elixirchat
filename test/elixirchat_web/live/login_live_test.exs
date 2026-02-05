defmodule ElixirchatWeb.LoginLiveTest do
  use ElixirchatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Elixirchat.Fixtures

  describe "LoginLive" do
    test "renders login form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/login")

      assert html =~ "Welcome Back"
      assert html =~ "Username"
      assert html =~ "Password"
      assert html =~ "Log In"
      assert has_element?(view, "form#login-form")
    end

    test "has link to signup page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, ~s|a[href="/signup"]|, "Sign up")
    end

    test "form posts to login action", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, ~s|form[action="/login"][method="post"]|)
    end
  end

  describe "login flow via controller" do
    test "login with valid credentials redirects", %{conn: conn} do
      user_fixture(%{username: "testlogin", password: "password123"})

      conn = post(conn, ~p"/login", %{"user" => %{"username" => "testlogin", "password" => "password123"}})

      # Redirects to home page after login
      assert redirected_to(conn) == ~p"/"
    end

    test "login with invalid password shows error", %{conn: conn} do
      user_fixture(%{username: "testlogin", password: "password123"})

      conn = post(conn, ~p"/login", %{"user" => %{"username" => "testlogin", "password" => "wrongpass"}})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "login with non-existent user shows error", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"user" => %{"username" => "nonexistent", "password" => "anypass"}})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end
  end
end

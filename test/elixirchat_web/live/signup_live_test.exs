defmodule ElixirchatWeb.SignupLiveTest do
  use ElixirchatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Elixirchat.Fixtures

  describe "SignupLive" do
    test "renders signup form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/signup")

      assert html =~ "Create Account"
      assert html =~ "Username"
      assert html =~ "Password"
      assert html =~ "Sign Up"
      assert has_element?(view, "form#signup-form")
    end

    test "shows validation errors on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      result =
        view
        |> form("#signup-form", user: %{username: "ab", password: "123"})
        |> render_change()

      assert result =~ "should be at least 3 character(s)"
      assert result =~ "should be at least 6 character(s)"
    end

    test "creates user successfully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> form("#signup-form", user: %{username: "newuser", password: "password123"})
      |> render_submit()

      flash = assert_redirect(view, ~p"/login")
      assert flash["info"] =~ "Account created successfully"
    end

    test "shows error for duplicate username", %{conn: conn} do
      user_fixture(%{username: "existinguser"})
      {:ok, view, _html} = live(conn, ~p"/signup")

      result =
        view
        |> form("#signup-form", user: %{username: "existinguser", password: "password123"})
        |> render_submit()

      assert result =~ "has already been taken"
    end

    test "has link to login page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      assert has_element?(view, ~s|a[href="/login"]|, "Log in")
    end
  end
end

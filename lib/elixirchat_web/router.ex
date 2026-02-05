defmodule ElixirchatWeb.Router do
  use ElixirchatWeb, :router

  import ElixirchatWeb.Plugs.Auth, only: [redirect_if_authenticated: 2, require_authenticated_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElixirchatWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ElixirchatWeb.Plugs.Auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ElixirchatWeb do
    pipe_through :browser

    get "/", PageController, :home
    delete "/logout", SessionController, :delete
  end

  # Routes for non-authenticated users
  scope "/", ElixirchatWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    live "/signup", SignupLive
    live "/login", LoginLive
    post "/login", SessionController, :create
  end

  # Routes for authenticated users
  scope "/", ElixirchatWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{ElixirchatWeb.Plugs.Auth, :ensure_authenticated}] do
      live "/chats", ChatListLive
      live "/chats/:id", ChatLive
      live "/groups/new", GroupNewLive
      live "/starred", StarredLive
      live "/settings", SettingsLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ElixirchatWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:elixirchat, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ElixirchatWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

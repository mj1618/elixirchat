defmodule ElixirchatWeb.LoginLive do
  use ElixirchatWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{"username" => "", "password" => ""}, as: "user"), error: nil)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-base-200 relative">
      <%!-- Theme toggle in corner --%>
      <div class="absolute top-4 right-4">
        <ElixirchatWeb.Layouts.theme_toggle />
      </div>
      <div class="card w-full max-w-md bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl font-bold justify-center">Welcome Back</h2>
          <p class="text-center text-base-content/70">Log in to continue chatting</p>

          <.form
            for={@form}
            id="login-form"
            action={~p"/login"}
            method="post"
            phx-update="ignore"
            class="space-y-4 mt-4"
          >
            <div :if={@error} class="alert alert-error">
              <span>{@error}</span>
            </div>

            <div class="form-control">
              <label class="label" for="username">
                <span class="label-text">Username</span>
              </label>
              <input
                type="text"
                name="user[username]"
                id="username"
                class="input input-bordered w-full"
                placeholder="Enter your username"
                required
              />
            </div>

            <div class="form-control">
              <label class="label" for="password">
                <span class="label-text">Password</span>
              </label>
              <input
                type="password"
                name="user[password]"
                id="password"
                class="input input-bordered w-full"
                placeholder="Enter your password"
                required
              />
            </div>

            <div class="form-control mt-6">
              <button type="submit" class="btn btn-primary w-full">
                Log In
              </button>
            </div>
          </.form>

          <div class="divider">OR</div>

          <p class="text-center">
            Don't have an account?
            <.link navigate={~p"/signup"} class="link link-primary">
              Sign up
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end

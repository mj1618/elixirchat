defmodule ElixirchatWeb.SignupLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Accounts
  alias Elixirchat.Accounts.User

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})
    {:ok, assign(socket, form: to_form(changeset), trigger_submit: false)}
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
          <h2 class="card-title text-2xl font-bold justify-center">Create Account</h2>
          <p class="text-center text-base-content/70">Sign up to start chatting</p>

          <.form
            for={@form}
            id="signup-form"
            phx-submit="save"
            phx-change="validate"
            class="space-y-4 mt-4"
          >
            <.input
              field={@form[:username]}
              type="text"
              label="Username"
              placeholder="Choose a username"
              required
            />

            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              placeholder="Choose a password"
              required
            />

            <div class="form-control mt-6">
              <button type="submit" class="btn btn-primary w-full">
                Sign Up
              </button>
            </div>
          </.form>

          <div class="divider">OR</div>

          <p class="text-center">
            Already have an account?
            <.link navigate={~p"/login"} class="link link-primary">
              Log in
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created successfully! Please log in.")
         |> redirect(to: ~p"/login")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end

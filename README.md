# Elixirchat

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

# Tech stack

Phoeonix + Elixir + PostrgeSQL deployed on fly.io

# Design

We're going to build a chat application similar to messenger, but there are no emails/phones to authenticate - you just create a (unique) username and password to signup/login, and you add people via their username. You can create group chats and add multiple username, or create a direct chat and search for a username as a singular chat.

Focus on getting this running locally first - and once the application is working locally we will deploy to fly.io


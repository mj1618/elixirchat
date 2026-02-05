# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Elixirchat.Repo.insert!(%Elixirchat.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Elixirchat.Repo
alias Elixirchat.Accounts.User
alias Elixirchat.Chat

# Ensure the General group conversation exists
{:ok, general} = Chat.get_or_create_general_conversation()
IO.puts("General group conversation ensured: #{general.name} (id: #{general.id})")

# Add all existing users to the General group
users = Repo.all(User)

Enum.each(users, fn user ->
  case Chat.add_user_to_general(user.id) do
    :ok ->
      IO.puts("Added user #{user.username} (id: #{user.id}) to General group")

    {:error, reason} ->
      IO.puts("Failed to add user #{user.username}: #{inspect(reason)}")
  end
end)

IO.puts("Seed complete. #{length(users)} users processed.")

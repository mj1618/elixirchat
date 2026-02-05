defmodule Elixirchat.Repo.Migrations.CreatePolls do
  use Ecto.Migration

  def change do
    # Create polls table
    create table(:polls) do
      add :question, :string, null: false, size: 500
      add :closed_at, :utc_datetime
      add :allow_multiple, :boolean, default: false
      add :anonymous, :boolean, default: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :creator_id, references(:users, on_delete: :nilify_all), null: false

      timestamps()
    end

    create index(:polls, [:conversation_id])
    create index(:polls, [:creator_id])

    # Create poll_options table
    create table(:poll_options) do
      add :text, :string, null: false, size: 200
      add :position, :integer, default: 0
      add :poll_id, references(:polls, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:poll_options, [:poll_id])

    # Create poll_votes table
    create table(:poll_votes) do
      add :poll_id, references(:polls, on_delete: :delete_all), null: false
      add :poll_option_id, references(:poll_options, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:poll_votes, [:poll_id])
    create index(:poll_votes, [:poll_option_id])
    create index(:poll_votes, [:user_id])
    create unique_index(:poll_votes, [:poll_id, :user_id, :poll_option_id])
  end
end

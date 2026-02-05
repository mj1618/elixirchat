# Task: Message Polls

## Description
Allow users to create polls in conversations that other members can vote on. Polls are a common feature in group chat applications (Telegram, Slack, Discord) that enable group decision-making, gathering opinions, and interactive engagement. Polls should support multiple choice questions with configurable options.

## Requirements
- Users can create a poll with a question and 2-10 answer options
- Poll appears as a special message type in the conversation
- Users can vote for one option (or multiple if enabled by creator)
- Vote counts and percentages are displayed in real-time
- Users can see who voted for each option (optional: creator can make votes anonymous)
- Poll creator can close the poll to stop accepting votes
- Users can change their vote until the poll is closed
- Polls work in both group chats and direct messages

## Implementation Steps

1. **Create Poll schema and migration** (`lib/elixirchat/chat/poll.ex`):
   - Fields: `question`, `conversation_id`, `creator_id`, `closed_at`, `allow_multiple`, `anonymous`
   - Migration for polls table

2. **Create PollOption schema and migration** (`lib/elixirchat/chat/poll_option.ex`):
   - Fields: `poll_id`, `text`, `position`
   - Migration for poll_options table

3. **Create PollVote schema and migration** (`lib/elixirchat/chat/poll_vote.ex`):
   - Fields: `poll_id`, `poll_option_id`, `user_id`
   - Unique constraint on `[:poll_id, :user_id, :poll_option_id]` for single-choice
   - Migration for poll_votes table

4. **Create migrations**:
   ```bash
   mix ecto.gen.migration create_polls
   mix ecto.gen.migration create_poll_options
   mix ecto.gen.migration create_poll_votes
   ```

5. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - `create_poll/4` - Create a poll with options
   - `vote_on_poll/3` - Cast or change a vote
   - `remove_vote/3` - Remove a vote
   - `close_poll/2` - Close poll to stop voting
   - `get_poll!/1` - Get poll with options and vote counts
   - `get_poll_results/1` - Get vote counts and voters per option

6. **Update ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add assigns for poll creation modal: `show_poll_modal`, `poll_question`, `poll_options`
   - Add "Create Poll" button near message input
   - Handle events: `show_poll_modal`, `close_poll_modal`, `add_poll_option`, `remove_poll_option`, `create_poll`, `vote_on_poll`, `close_poll`
   - Render polls as special message type
   - Subscribe to poll updates via PubSub

7. **Create poll UI components**:
   - Poll creation modal with question + options inputs
   - Poll display component showing question, options, vote counts
   - Vote buttons for each option
   - Results visualization (progress bars)
   - Close poll button (for creator only)

## Technical Details

### Poll Schema
```elixir
defmodule Elixirchat.Chat.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User
  alias Elixirchat.Chat.{Conversation, PollOption, PollVote}

  schema "polls" do
    field :question, :string
    field :closed_at, :utc_datetime
    field :allow_multiple, :boolean, default: false
    field :anonymous, :boolean, default: false

    belongs_to :conversation, Conversation
    belongs_to :creator, User
    has_many :options, PollOption, on_delete: :delete_all
    has_many :votes, PollVote, on_delete: :delete_all

    timestamps()
  end

  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [:question, :conversation_id, :creator_id, :allow_multiple, :anonymous, :closed_at])
    |> validate_required([:question, :conversation_id, :creator_id])
    |> validate_length(:question, min: 1, max: 500)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:creator_id)
  end
end
```

### PollOption Schema
```elixir
defmodule Elixirchat.Chat.PollOption do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Poll, PollVote}

  schema "poll_options" do
    field :text, :string
    field :position, :integer

    belongs_to :poll, Poll
    has_many :votes, PollVote, on_delete: :delete_all

    timestamps()
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :position, :poll_id])
    |> validate_required([:text, :poll_id])
    |> validate_length(:text, min: 1, max: 200)
    |> foreign_key_constraint(:poll_id)
  end
end
```

### PollVote Schema
```elixir
defmodule Elixirchat.Chat.PollVote do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User
  alias Elixirchat.Chat.{Poll, PollOption}

  schema "poll_votes" do
    belongs_to :poll, Poll
    belongs_to :poll_option, PollOption
    belongs_to :user, User

    timestamps()
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:poll_id, :poll_option_id, :user_id])
    |> validate_required([:poll_id, :poll_option_id, :user_id])
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:poll_option_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:poll_id, :user_id, :poll_option_id])
  end
end
```

### Migration - Polls
```elixir
defmodule Elixirchat.Repo.Migrations.CreatePolls do
  use Ecto.Migration

  def change do
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
  end
end
```

### Migration - Poll Options
```elixir
defmodule Elixirchat.Repo.Migrations.CreatePollOptions do
  use Ecto.Migration

  def change do
    create table(:poll_options) do
      add :text, :string, null: false, size: 200
      add :position, :integer, default: 0
      add :poll_id, references(:polls, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:poll_options, [:poll_id])
  end
end
```

### Migration - Poll Votes
```elixir
defmodule Elixirchat.Repo.Migrations.CreatePollVotes do
  use Ecto.Migration

  def change do
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
```

### Chat Context Functions
```elixir
alias Elixirchat.Chat.{Poll, PollOption, PollVote}

def create_poll(conversation_id, creator_id, question, options) when is_list(options) do
  # Validate options count
  if length(options) < 2 or length(options) > 10 do
    {:error, :invalid_options_count}
  else
    Repo.transaction(fn ->
      # Create poll
      {:ok, poll} =
        %Poll{}
        |> Poll.changeset(%{
          question: question,
          conversation_id: conversation_id,
          creator_id: creator_id
        })
        |> Repo.insert()

      # Create options
      options
      |> Enum.with_index()
      |> Enum.each(fn {text, index} ->
        %PollOption{}
        |> PollOption.changeset(%{
          text: text,
          position: index,
          poll_id: poll.id
        })
        |> Repo.insert!()
      end)

      # Preload and broadcast
      poll = get_poll!(poll.id)
      broadcast_poll_created(conversation_id, poll)
      poll
    end)
  end
end

def get_poll!(poll_id) do
  Poll
  |> Repo.get!(poll_id)
  |> Repo.preload([:creator, options: :votes])
  |> compute_poll_results()
end

defp compute_poll_results(poll) do
  total_votes = Enum.sum(Enum.map(poll.options, fn opt -> length(opt.votes) end))
  
  options_with_counts = Enum.map(poll.options, fn option ->
    vote_count = length(option.votes)
    percentage = if total_votes > 0, do: round(vote_count / total_votes * 100), else: 0
    voters = if poll.anonymous, do: [], else: Enum.map(option.votes, & &1.user_id)
    
    Map.merge(option, %{
      vote_count: vote_count,
      percentage: percentage,
      voters: voters
    })
  end)
  
  Map.merge(poll, %{
    options: options_with_counts,
    total_votes: total_votes
  })
end

def vote_on_poll(poll_id, option_id, user_id) do
  poll = Repo.get!(Poll, poll_id)
  
  cond do
    poll.closed_at ->
      {:error, :poll_closed}
    
    not poll.allow_multiple ->
      # Single choice: remove existing vote first
      from(v in PollVote, where: v.poll_id == ^poll_id and v.user_id == ^user_id)
      |> Repo.delete_all()
      
      insert_vote(poll_id, option_id, user_id)
    
    true ->
      # Multiple choice: just add vote
      insert_vote(poll_id, option_id, user_id)
  end
end

defp insert_vote(poll_id, option_id, user_id) do
  %PollVote{}
  |> PollVote.changeset(%{
    poll_id: poll_id,
    poll_option_id: option_id,
    user_id: user_id
  })
  |> Repo.insert()
  |> case do
    {:ok, _vote} ->
      poll = get_poll!(poll_id)
      broadcast_poll_updated(poll)
      {:ok, poll}
    error -> error
  end
end

def remove_vote(poll_id, option_id, user_id) do
  from(v in PollVote,
    where: v.poll_id == ^poll_id and v.poll_option_id == ^option_id and v.user_id == ^user_id
  )
  |> Repo.delete_all()
  
  poll = get_poll!(poll_id)
  broadcast_poll_updated(poll)
  {:ok, poll}
end

def close_poll(poll_id, user_id) do
  poll = Repo.get!(Poll, poll_id)
  
  if poll.creator_id != user_id do
    {:error, :not_creator}
  else
    poll
    |> Poll.changeset(%{closed_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
    |> case do
      {:ok, poll} ->
        poll = get_poll!(poll_id)
        broadcast_poll_updated(poll)
        {:ok, poll}
      error -> error
    end
  end
end

defp broadcast_poll_created(conversation_id, poll) do
  Phoenix.PubSub.broadcast(
    Elixirchat.PubSub,
    "conversation:#{conversation_id}",
    {:poll_created, poll}
  )
end

defp broadcast_poll_updated(poll) do
  Phoenix.PubSub.broadcast(
    Elixirchat.PubSub,
    "conversation:#{poll.conversation_id}",
    {:poll_updated, poll}
  )
end

def list_conversation_polls(conversation_id) do
  from(p in Poll,
    where: p.conversation_id == ^conversation_id,
    order_by: [desc: p.inserted_at],
    preload: [:creator, options: :votes]
  )
  |> Repo.all()
  |> Enum.map(&compute_poll_results/1)
end
```

### ChatLive - Poll Modal UI
```heex
<%!-- Create Poll button near message input --%>
<button
  phx-click="show_poll_modal"
  class="btn btn-ghost btn-circle btn-sm"
  title="Create poll"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
    <path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z" />
  </svg>
</button>

<%!-- Poll creation modal --%>
<div :if={@show_poll_modal} class="modal modal-open">
  <div class="modal-box">
    <h3 class="font-bold text-lg mb-4">Create Poll</h3>
    
    <form phx-submit="create_poll">
      <div class="form-control mb-4">
        <label class="label">
          <span class="label-text">Question</span>
        </label>
        <input
          type="text"
          name="question"
          value={@poll_question}
          phx-change="update_poll_question"
          placeholder="Ask a question..."
          class="input input-bordered w-full"
          required
          maxlength="500"
        />
      </div>
      
      <div class="form-control mb-4">
        <label class="label">
          <span class="label-text">Options</span>
          <span class="label-text-alt">{length(@poll_options)}/10</span>
        </label>
        
        <div class="space-y-2">
          <div :for={{option, index} <- Enum.with_index(@poll_options)} class="flex gap-2">
            <input
              type="text"
              name={"options[#{index}]"}
              value={option}
              phx-change="update_poll_option"
              phx-value-index={index}
              placeholder={"Option #{index + 1}"}
              class="input input-bordered flex-1"
              required
              maxlength="200"
            />
            <button
              :if={length(@poll_options) > 2}
              type="button"
              phx-click="remove_poll_option"
              phx-value-index={index}
              class="btn btn-ghost btn-circle btn-sm"
            >
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
        
        <button
          :if={length(@poll_options) < 10}
          type="button"
          phx-click="add_poll_option"
          class="btn btn-ghost btn-sm mt-2"
        >
          + Add option
        </button>
      </div>
      
      <div class="modal-action">
        <button type="button" phx-click="close_poll_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary" disabled={length(@poll_options) < 2}>
          Create Poll
        </button>
      </div>
    </form>
  </div>
  <div class="modal-backdrop bg-base-content/50" phx-click="close_poll_modal"></div>
</div>
```

### ChatLive - Poll Display Component
```heex
<%!-- Poll display in messages area --%>
<div :for={poll <- @polls} class="card bg-base-200 shadow-lg my-4 mx-auto max-w-md">
  <div class="card-body">
    <div class="flex justify-between items-start">
      <div>
        <h3 class="card-title text-base">{poll.question}</h3>
        <p class="text-xs text-base-content/60">
          by @{poll.creator.username}
          {if poll.closed_at, do: " • Closed", else: " • " <> "#{poll.total_votes} votes"}
        </p>
      </div>
      <button
        :if={poll.creator_id == @current_user.id && is_nil(poll.closed_at)}
        phx-click="close_poll"
        phx-value-poll-id={poll.id}
        class="btn btn-ghost btn-xs"
        title="Close poll"
      >
        Close
      </button>
    </div>
    
    <div class="space-y-2 mt-4">
      <div :for={option <- poll.options} class="relative">
        <button
          phx-click="vote_on_poll"
          phx-value-poll-id={poll.id}
          phx-value-option-id={option.id}
          disabled={poll.closed_at != nil}
          class={[
            "w-full text-left p-3 rounded-lg border transition-colors",
            option.id in @user_poll_votes[poll.id] && "border-primary bg-primary/10" || "border-base-300 hover:border-primary"
          ]}
        >
          <div class="flex justify-between items-center relative z-10">
            <span class="font-medium">{option.text}</span>
            <span class="text-sm">{option.percentage}%</span>
          </div>
          <%!-- Progress bar --%>
          <div 
            class="absolute inset-0 bg-primary/20 rounded-lg transition-all"
            style={"width: #{option.percentage}%"}
          />
        </button>
        <div :if={not poll.anonymous && option.vote_count > 0} class="text-xs text-base-content/60 mt-1 pl-2">
          {option.vote_count} {if option.vote_count == 1, do: "vote", else: "votes"}
        </div>
      </div>
    </div>
  </div>
</div>
```

### Event Handlers
```elixir
def mount(_params, _session, socket) do
  # ... existing mount code ...
  |> assign(
    show_poll_modal: false,
    poll_question: "",
    poll_options: ["", ""],
    polls: [],
    user_poll_votes: %{}
  )
end

def handle_event("show_poll_modal", _, socket) do
  {:noreply, assign(socket, show_poll_modal: true, poll_question: "", poll_options: ["", ""])}
end

def handle_event("close_poll_modal", _, socket) do
  {:noreply, assign(socket, show_poll_modal: false)}
end

def handle_event("update_poll_question", %{"question" => question}, socket) do
  {:noreply, assign(socket, poll_question: question)}
end

def handle_event("update_poll_option", %{"index" => index, "value" => value}, socket) do
  index = String.to_integer(index)
  options = List.replace_at(socket.assigns.poll_options, index, value)
  {:noreply, assign(socket, poll_options: options)}
end

def handle_event("add_poll_option", _, socket) do
  options = socket.assigns.poll_options ++ [""]
  {:noreply, assign(socket, poll_options: options)}
end

def handle_event("remove_poll_option", %{"index" => index}, socket) do
  index = String.to_integer(index)
  options = List.delete_at(socket.assigns.poll_options, index)
  {:noreply, assign(socket, poll_options: options)}
end

def handle_event("create_poll", %{"question" => question} = params, socket) do
  options = 
    params
    |> Map.get("options", %{})
    |> Map.values()
    |> Enum.filter(& &1 != "")
  
  case Chat.create_poll(
    socket.assigns.conversation.id,
    socket.assigns.current_user.id,
    question,
    options
  ) do
    {:ok, poll} ->
      {:noreply,
       socket
       |> assign(show_poll_modal: false)
       |> update(:polls, fn polls -> [poll | polls] end)
       |> put_flash(:info, "Poll created")}
    
    {:error, :invalid_options_count} ->
      {:noreply, put_flash(socket, :error, "Poll must have 2-10 options")}
    
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not create poll")}
  end
end

def handle_event("vote_on_poll", %{"poll-id" => poll_id, "option-id" => option_id}, socket) do
  poll_id = String.to_integer(poll_id)
  option_id = String.to_integer(option_id)
  
  case Chat.vote_on_poll(poll_id, option_id, socket.assigns.current_user.id) do
    {:ok, poll} ->
      {:noreply, update_poll_in_list(socket, poll)}
    
    {:error, :poll_closed} ->
      {:noreply, put_flash(socket, :error, "This poll is closed")}
    
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not vote")}
  end
end

def handle_event("close_poll", %{"poll-id" => poll_id}, socket) do
  poll_id = String.to_integer(poll_id)
  
  case Chat.close_poll(poll_id, socket.assigns.current_user.id) do
    {:ok, poll} ->
      {:noreply,
       socket
       |> update_poll_in_list(poll)
       |> put_flash(:info, "Poll closed")}
    
    {:error, :not_creator} ->
      {:noreply, put_flash(socket, :error, "Only the poll creator can close it")}
    
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Could not close poll")}
  end
end

def handle_info({:poll_created, poll}, socket) do
  {:noreply, update(socket, :polls, fn polls -> [poll | polls] end)}
end

def handle_info({:poll_updated, poll}, socket) do
  {:noreply, update_poll_in_list(socket, poll)}
end

defp update_poll_in_list(socket, updated_poll) do
  polls = Enum.map(socket.assigns.polls, fn poll ->
    if poll.id == updated_poll.id, do: updated_poll, else: poll
  end)
  assign(socket, polls: polls)
end
```

## Acceptance Criteria
- [ ] "Create Poll" button appears near message input area
- [ ] Poll creation modal with question and options fields
- [ ] Can add/remove poll options (min 2, max 10)
- [ ] Created poll appears in conversation for all members
- [ ] Users can click an option to vote
- [ ] Vote counts and percentages update in real-time
- [ ] Poll creator can close the poll
- [ ] Closed polls show final results but don't accept votes
- [ ] User's selected option is visually highlighted
- [ ] Users can change their vote (before poll closes)
- [ ] Polls persist across page refreshes
- [ ] Works in both direct messages and group chats

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Create a poll with 3 options
- Vote on an option and verify vote count updates
- Have another user vote and verify real-time update
- Change your vote and verify it updates correctly
- Close the poll as creator
- Verify closed poll no longer accepts votes
- Create poll with min (2) and max (10) options
- Test in group chat with multiple users voting
- Refresh page and verify poll state persists

## Edge Cases to Handle
- Creating poll with empty options (should filter them out)
- User tries to vote after poll closed (error message)
- Non-creator tries to close poll (error)
- Poll creator leaves/is removed from conversation
- Very long question or option text (truncate display)
- Rapid voting by same user
- All users in conversation vote (100% total)
- Poll with no votes yet (show 0% for all)
- User votes then deletes account (cascade delete votes)

## Future Enhancements (not in this task)
- Multiple choice polls (vote for multiple options)
- Anonymous voting option
- Poll expiration time
- Edit poll after creation
- Poll templates/quick polls
- Show voter names on hover
- Export poll results
- Quizzes (polls with correct answers)

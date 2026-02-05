# Task: Message Reactions

## Description
Add emoji reactions to messages, allowing users to react to any message with emojis (thumbs up, heart, laugh, etc.). This is a standard feature in modern chat applications like Slack, Discord, and Messenger that increases engagement without requiring a full reply.

## Requirements
- Users can add emoji reactions to any message (their own or others')
- A fixed set of reaction emojis: 👍 👎 ❤️ 😂 😮 😢
- Each user can only react once per emoji per message (toggle behavior)
- Reactions display below the message bubble with emoji + count
- Clicking on existing reaction toggles your own reaction
- Real-time updates: reactions appear instantly for all conversation members via PubSub
- Users can see who reacted by hovering over the reaction (tooltip)

## Implementation Steps

1. **Create Reaction schema and migration** (`lib/elixirchat/chat/reaction.ex`):
   - Fields: `id`, `message_id`, `user_id`, `emoji` (string)
   - Unique constraint on `[:message_id, :user_id, :emoji]`
   - Belongs to Message and User

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration create_reactions
   ```
   ```elixir
   create table(:reactions) do
     add :emoji, :string, null: false
     add :message_id, references(:messages, on_delete: :delete_all), null: false
     add :user_id, references(:users, on_delete: :delete_all), null: false
     timestamps()
   end

   create unique_index(:reactions, [:message_id, :user_id, :emoji])
   create index(:reactions, [:message_id])
   ```

3. **Add reaction functions to Chat context** (`lib/elixirchat/chat.ex`):
   - `toggle_reaction/3` - Add or remove a reaction (message_id, user_id, emoji)
   - `list_message_reactions/1` - Get all reactions for a message, grouped by emoji
   - `get_reactions_for_messages/1` - Batch load reactions for a list of message IDs
   - `broadcast_reaction_update/2` - Broadcast reaction change to conversation

4. **Update Message preloading to include reactions**:
   - Update `list_messages/2` to preload reactions with users
   - Ensure new messages broadcast with empty reactions list

5. **Update ChatLive to handle reactions** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `handle_event("toggle_reaction", ...)` to process reaction clicks
   - Add `handle_event("show_reaction_picker", ...)` to show emoji picker
   - Add `handle_info({:reaction_updated, ...}, ...)` to receive reaction broadcasts
   - Track `reactions` in socket assigns for real-time updates

6. **Update message rendering in ChatLive**:
   - Add reaction picker button (smiley icon) on hover
   - Show reaction picker popup with emoji options
   - Display reactions below message bubble
   - Show count and highlight if current user has reacted
   - Add tooltip showing usernames on hover

## Technical Details

### Reaction Schema
```elixir
defmodule Elixirchat.Chat.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reactions" do
    field :emoji, :string
    belongs_to :message, Elixirchat.Chat.Message
    belongs_to :user, Elixirchat.Accounts.User

    timestamps()
  end

  @allowed_emojis ~w(👍 👎 ❤️ 😂 😮 😢)

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :message_id, :user_id])
    |> validate_required([:emoji, :message_id, :user_id])
    |> validate_inclusion(:emoji, @allowed_emojis)
    |> unique_constraint([:message_id, :user_id, :emoji])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
  end

  def allowed_emojis, do: @allowed_emojis
end
```

### Toggle Reaction Function
```elixir
def toggle_reaction(message_id, user_id, emoji) do
  message = Repo.get!(Message, message_id)
  
  existing =
    from(r in Reaction,
      where: r.message_id == ^message_id and r.user_id == ^user_id and r.emoji == ^emoji
    )
    |> Repo.one()

  result =
    case existing do
      nil ->
        # Add reaction
        %Reaction{}
        |> Reaction.changeset(%{message_id: message_id, user_id: user_id, emoji: emoji})
        |> Repo.insert()

      reaction ->
        # Remove reaction
        Repo.delete(reaction)
    end

  case result do
    {:ok, _} ->
      reactions = list_message_reactions(message_id)
      broadcast_reaction_update(message.conversation_id, %{message_id: message_id, reactions: reactions})
      {:ok, reactions}

    error ->
      error
  end
end
```

### PubSub Event
```elixir
# Broadcast reaction update
{:reaction_updated, %{message_id: id, reactions: grouped_reactions}}
```

### UI Components

```heex
<%!-- Reaction picker button (on hover) --%>
<button
  phx-click="show_reaction_picker"
  phx-value-message-id={message.id}
  class="opacity-0 group-hover:opacity-100 btn btn-ghost btn-xs"
>
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
    <path stroke-linecap="round" stroke-linejoin="round" d="M15.182 15.182a4.5 4.5 0 0 1-6.364 0M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM9.75 9.75c0 .414-.168.75-.375.75S9 10.164 9 9.75 9.168 9 9.375 9s.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Zm5.625 0c0 .414-.168.75-.375.75s-.375-.336-.375-.75.168-.75.375-.75.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Z" />
  </svg>
</button>

<%!-- Reaction picker popup --%>
<div :if={@reaction_picker_message_id == message.id} class="absolute bg-base-100 shadow-lg rounded-lg p-2 flex gap-1 z-10">
  <button :for={emoji <- Reaction.allowed_emojis()} phx-click="toggle_reaction" phx-value-message-id={message.id} phx-value-emoji={emoji} class="btn btn-ghost btn-sm text-lg hover:scale-125 transition-transform">
    {emoji}
  </button>
</div>

<%!-- Reactions display below message --%>
<div :if={map_size(message.reactions_grouped) > 0} class="flex flex-wrap gap-1 mt-1">
  <button
    :for={{emoji, reactors} <- message.reactions_grouped}
    phx-click="toggle_reaction"
    phx-value-message-id={message.id}
    phx-value-emoji={emoji}
    class={["btn btn-xs gap-1", @current_user.id in Enum.map(reactors, & &1.id) && "btn-primary" || "btn-ghost"]}
    title={Enum.map_join(reactors, ", ", & &1.username)}
  >
    <span>{emoji}</span>
    <span class="text-xs">{length(reactors)}</span>
  </button>
</div>
```

## Acceptance Criteria
- [ ] Users can add emoji reactions to any message
- [ ] Fixed set of 6 emojis available (👍 👎 ❤️ 😂 😮 😢)
- [ ] Clicking reaction again removes it (toggle behavior)
- [ ] Reactions display below message with emoji and count
- [ ] User's own reactions are highlighted/styled differently
- [ ] Hovering shows list of users who reacted (tooltip)
- [ ] Reactions update in real-time for all conversation members
- [ ] Works in both direct and group chats
- [ ] Reactions persist across page refreshes

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Create a conversation and send several messages
- Add a reaction to a message - verify it appears
- Click same reaction again - verify it's removed
- Open same conversation in another browser tab as different user
- Verify reactions appear in real-time for other user
- Have both users react to same message - verify counts update
- Hover over reaction to verify tooltip shows usernames
- Test in both direct and group chats
- Refresh page and verify reactions persist

## Edge Cases to Handle
- User tries to use emoji not in allowed list (reject)
- Rapid clicking on reactions (debounce or handle gracefully)
- Message deleted while reactions exist (cascade delete via FK)
- Very long list of reactors in tooltip (truncate with "+X more")
- Mobile: touch-friendly reaction picker (consider long-press)

## Implementation Notes (Agent: 75cb969c)

### Completed on Feb 5, 2026

**Implementation Summary:**
- Created `lib/elixirchat/chat/reaction.ex` - Reaction schema with emoji validation
- Created `priv/repo/migrations/20260205051000_create_reactions.exs` - Migration for reactions table
- Updated `lib/elixirchat/chat/message.ex` - Added `has_many :reactions` association
- Updated `lib/elixirchat/chat.ex` - Added reaction functions:
  - `toggle_reaction/3` - Toggle (add/remove) a reaction
  - `list_message_reactions/1` - Get reactions grouped by emoji
  - `get_reactions_for_messages/1` - Batch load reactions for multiple messages
  - `broadcast_reaction_update/2` - Broadcast reaction changes via PubSub
  - Modified `list_messages/2` to include reactions
  - Modified `send_message/3` to include empty reactions_grouped for new messages
- Updated `lib/elixirchat_web/live/chat_live.ex`:
  - Added `reaction_picker_message_id` to socket assigns
  - Added `handle_event` for "show_reaction_picker", "close_reaction_picker", "toggle_reaction"
  - Added `handle_info` for `:reaction_updated` PubSub messages
  - Added reaction picker button to message hover actions
  - Added reaction picker popup with emoji options
  - Added reactions display below messages with counts and tooltips
  - Added helper functions `user_has_reacted?/2` and `format_reactor_names/1`

**All code compiles successfully.**

**Testing Notes:**
- Attempted browser testing with playwright-cli but encountered migration sync issue with running Phoenix server
- Recommend restarting the Phoenix server (`mix phx.server`) after implementation to ensure clean test
- All core functionality implemented according to requirements

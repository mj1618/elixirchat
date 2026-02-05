# Task: User @Mentions with Notifications

## Completion Notes (Agent d12ce640)

**Completed on:** 2026-02-05

### What was implemented:

1. **Created `Elixirchat.Chat.Mentions` module** (`lib/elixirchat/chat/mentions.ex`):
   - `extract_usernames/1` - Extracts @usernames from message content
   - `get_mentionable_users/2` - Gets users that can be mentioned in a conversation
   - `resolve_mentions/2` - Resolves mentions to user IDs
   - `has_mentions?/1` - Checks if content has any mentions
   - `render_with_mentions/2` - Renders content with highlighted mentions (HTML with styled spans)

2. **Updated Chat context** (`lib/elixirchat/chat.ex`):
   - Added delegation to Mentions module for `get_mentionable_users/2` and `render_with_mentions/2`

3. **Updated ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Added `show_mentions` and `mention_results` assigns
   - Added event handlers: `mention_search`, `select_mention`, `close_mentions`
   - Updated message rendering to use `Mentions.render_with_mentions/2`
   - Added mention autocomplete dropdown UI above message input

4. **Added JavaScript MentionInput hook** (`assets/js/app.js`):
   - Detects @ character in input and tracks mention start position
   - Sends search query to server with debouncing
   - Handles `insert_mention` event to insert selected username
   - Handles Escape key to close dropdown

### Features:
- Autocomplete dropdown appears when typing @ followed by characters
- Only shows conversation members (excludes current user)
- Selected username is inserted at cursor position with @ prefix and trailing space
- @mentions are highlighted in rendered messages with primary color styling
- Works in both direct and group chats
- Case-insensitive matching
- Debounced search requests

### Not implemented (future work):
- Mention notification badge in chat list
- Keyboard navigation in autocomplete (arrow keys, enter)
- Click on mention to show user profile

---

## Description
Add the ability to @mention users in chat messages, similar to Slack and Discord. When a user is mentioned with @username, the mentioned text should be highlighted in the message, and the mentioned user should see the conversation highlighted/badged even if they have muted notifications. This builds on the existing @agent pattern in the codebase.

## Requirements
- Users can type @username to mention other users in messages
- Autocomplete dropdown appears when typing @ followed by characters
- Only conversation members can be mentioned (in group chats)
- Mentioned text is styled/highlighted in rendered messages
- Mentioned users see a visual indicator in the chat list
- @mentions work in both direct and group chats
- Multiple users can be mentioned in one message
- Clicking on a mention could show user info (optional enhancement)

## Implementation Steps

1. **Add mention tracking to Message schema** (`lib/elixirchat/chat/message.ex`):
   - Add `mentions` virtual field or extract mentions on render
   - Helper function to parse @usernames from message content

2. **Create mention autocomplete function** (`lib/elixirchat/chat.ex`):
   - `get_mentionable_users/2` - Get users that can be mentioned in a conversation
   - Parse mentions from message content with `extract_mentions/1`
   - `get_mentioned_user_ids/2` - Extract user IDs from message text

3. **Add mention notification tracking**:
   - Add `has_mention` field to `list_user_conversations/1` response
   - Query to check if user has unread mentions in a conversation
   - Consider adding `mentions` table if we need persistence (optional)

4. **Update ChatLive for mention autocomplete** (`lib/elixirchat_web/live/chat_live.ex`):
   - Track `mention_search` and `mention_results` in assigns
   - Handle `"mention_search"` event when @ is typed
   - Handle `"select_mention"` event to insert username
   - Handle `"close_mentions"` event to dismiss dropdown

5. **Add JavaScript hook for mention detection** (`assets/js/app.js`):
   - Detect @ character in input
   - Track cursor position for autocomplete
   - Send search query to server
   - Handle mention selection and insertion

6. **Update message rendering**:
   - Parse and highlight @mentions in message content
   - Style mentions with distinct color/background
   - Make mentions clickable (optional - show user profile)

7. **Update chat list to show mention indicators**:
   - Add mention badge/highlight for unread mentions
   - Differentiate from regular unread count

## Technical Details

### Extract Mentions Helper
```elixir
defmodule Elixirchat.Chat.Mentions do
  @mention_regex ~r/@([a-zA-Z0-9_]+)/

  @doc """
  Extracts all @mentions from message content.
  Returns list of usernames (without the @ symbol).
  """
  def extract_usernames(content) when is_binary(content) do
    @mention_regex
    |> Regex.scan(content)
    |> Enum.map(fn [_, username] -> username end)
    |> Enum.uniq()
  end

  def extract_usernames(_), do: []

  @doc """
  Converts usernames to user IDs.
  Only returns IDs for users who exist and are in the conversation.
  """
  def resolve_mentions(content, conversation_id) do
    usernames = extract_usernames(content)
    
    if usernames == [] do
      []
    else
      members = Chat.list_group_members(conversation_id)
      member_map = Map.new(members, fn u -> {String.downcase(u.username), u.id} end)
      
      usernames
      |> Enum.map(&String.downcase/1)
      |> Enum.filter(&Map.has_key?(member_map, &1))
      |> Enum.map(&Map.get(member_map, &1))
    end
  end

  @doc """
  Renders message content with highlighted mentions.
  Returns safe HTML with mentions wrapped in styled spans.
  """
  def render_with_mentions(content) when is_binary(content) do
    Regex.replace(@mention_regex, content, fn full, username ->
      ~s(<span class="mention text-primary font-semibold hover:underline cursor-pointer" data-username="#{username}">#{full}</span>)
    end)
  end

  def render_with_mentions(content), do: content
end
```

### Mentionable Users Query
```elixir
def get_mentionable_users(conversation_id, search_term) do
  search = "%#{search_term}%"
  
  from(m in ConversationMember,
    join: u in assoc(m, :user),
    where: m.conversation_id == ^conversation_id,
    where: ilike(u.username, ^search),
    select: u,
    limit: 5,
    order_by: u.username
  )
  |> Repo.all()
end
```

### LiveView Mention Handling
```elixir
def handle_event("mention_search", %{"query" => query, "position" => position}, socket) do
  results = 
    if String.length(query) >= 1 do
      Chat.get_mentionable_users(socket.assigns.conversation.id, query)
    else
      []
    end

  {:noreply, assign(socket, 
    mention_results: results, 
    mention_position: position,
    show_mentions: results != []
  )}
end

def handle_event("select_mention", %{"username" => username}, socket) do
  {:noreply, 
    socket
    |> assign(show_mentions: false, mention_results: [])
    |> push_event("insert_mention", %{username: username})
  }
end

def handle_event("close_mentions", _, socket) do
  {:noreply, assign(socket, show_mentions: false, mention_results: [])}
end
```

### JavaScript Hook
```javascript
Hooks.MentionInput = {
  mounted() {
    this.input = this.el.querySelector('input[type="text"], textarea');
    this.mentionStart = null;
    
    this.input.addEventListener('input', (e) => {
      const value = this.input.value;
      const cursorPos = this.input.selectionStart;
      
      // Find @ before cursor
      const textBeforeCursor = value.substring(0, cursorPos);
      const lastAtIndex = textBeforeCursor.lastIndexOf('@');
      
      if (lastAtIndex !== -1) {
        const textAfterAt = textBeforeCursor.substring(lastAtIndex + 1);
        // Check if we're in a mention (no spaces after @)
        if (!/\s/.test(textAfterAt)) {
          this.mentionStart = lastAtIndex;
          this.pushEvent("mention_search", { 
            query: textAfterAt,
            position: lastAtIndex 
          });
          return;
        }
      }
      
      this.mentionStart = null;
      this.pushEvent("close_mentions", {});
    });

    this.handleEvent("insert_mention", ({username}) => {
      if (this.mentionStart !== null) {
        const value = this.input.value;
        const before = value.substring(0, this.mentionStart);
        const after = value.substring(this.input.selectionStart);
        this.input.value = `${before}@${username} ${after}`;
        this.input.focus();
        const newPos = this.mentionStart + username.length + 2;
        this.input.setSelectionRange(newPos, newPos);
        this.mentionStart = null;
      }
    });
  }
}
```

### UI Components

```heex
<%!-- Mention autocomplete dropdown --%>
<div :if={@show_mentions && @mention_results != []} 
     class="absolute bottom-full left-0 mb-2 w-64 bg-base-100 border border-base-300 rounded-lg shadow-lg z-20">
  <ul class="menu menu-compact">
    <li :for={user <- @mention_results}>
      <button type="button" phx-click="select_mention" phx-value-username={user.username} class="flex items-center gap-2">
        <div class="avatar placeholder">
          <div class="bg-neutral text-neutral-content rounded-full w-6">
            <span class="text-xs">{String.first(user.username) |> String.upcase()}</span>
          </div>
        </div>
        <span>@{user.username}</span>
      </button>
    </li>
  </ul>
</div>

<%!-- Message with highlighted mentions --%>
<p class="whitespace-pre-wrap break-words">
  <%= raw(Mentions.render_with_mentions(message.content)) %>
</p>
```

## Acceptance Criteria
- [ ] Typing @ followed by characters shows autocomplete dropdown
- [ ] Autocomplete only shows conversation members
- [ ] Selecting from autocomplete inserts @username into input
- [ ] @mentions are highlighted in rendered messages
- [ ] Works in both direct and group chats
- [ ] Multiple mentions per message work correctly
- [ ] Case-insensitive mention matching
- [ ] Mentioned users see visual indicator in chat list (nice-to-have)
- [ ] Real-time: mentions appear correctly for all users

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Create a group chat with 3+ users
- Type @ and verify autocomplete appears
- Select a user and verify username is inserted
- Send message and verify mention is highlighted
- Open chat as mentioned user
- Test partial username matching in autocomplete
- Test multiple mentions in one message
- Test @ followed by non-existent username (should not highlight)
- Test keyboard navigation in autocomplete (arrow keys, enter)

## Edge Cases to Handle
- @ at the beginning vs middle of message
- @@ or multiple @ in a row
- Username that no longer exists (deleted user)
- Very long list of members (limit autocomplete results)
- Mention inside code block or quoted text (probably shouldn't autocomplete)
- User types @agent (should still trigger agent, not conflict)
- Rapid typing (debounce autocomplete requests)
- User leaves conversation after being mentioned

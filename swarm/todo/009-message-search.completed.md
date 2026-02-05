# Task: Message Search

## Description
Add the ability to search through messages in conversations. Users should be able to search for specific text within a conversation to find past messages quickly. This is a common feature in chat applications that significantly improves user experience, especially in conversations with many messages.

## Requirements
- Search box in the chat view header to search within current conversation
- Search results highlight matching text
- Clicking a search result scrolls to that message
- Search is case-insensitive
- Debounced search input to avoid excessive queries
- Clear search button to reset results
- Show "no results" feedback when no matches found

## Implementation Steps

1. **Add search function to Chat context** (`lib/elixirchat/chat.ex`):
   - `search_messages/2` - searches messages in a conversation by text
   - Uses PostgreSQL `ILIKE` for case-insensitive matching
   - Returns messages with sender info preloaded
   - Limits results to prevent large responses

2. **Update ChatLive to support search** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add `search_query` and `search_results` to socket assigns
   - Add `show_search` boolean to toggle search UI
   - Handle `toggle_search` event
   - Handle `search_messages` event with debounce
   - Handle `clear_search` event
   - Handle `jump_to_message` event to scroll to a specific message

3. **Update Chat UI with search functionality**:
   - Add search icon button in header (next to members dropdown)
   - Show search input when toggled
   - Display search results in a dropdown/overlay
   - Each result shows: sender, message snippet, timestamp
   - Highlight matching text in results
   - Style search results to be visually distinct

4. **Add scroll-to-message functionality**:
   - Add message IDs as HTML element IDs
   - Use JavaScript hook to scroll to specific message
   - Optionally highlight the scrolled-to message briefly

5. **Performance considerations**:
   - Add database index on `messages.content` for faster text search
   - Consider using PostgreSQL full-text search for better performance
   - Limit search to recent messages initially, with "load more" option

## Technical Details

### Search Function
```elixir
def search_messages(conversation_id, query) when byte_size(query) >= 2 do
  search_term = "%#{query}%"
  
  from(m in Message,
    where: m.conversation_id == ^conversation_id,
    where: ilike(m.content, ^search_term),
    order_by: [desc: m.inserted_at],
    limit: 20,
    preload: [:sender]
  )
  |> Repo.all()
end

def search_messages(_, _), do: []
```

### UI Component
```heex
<%!-- Search toggle button --%>
<button phx-click="toggle_search" class="btn btn-ghost btn-sm">
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
    <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z" />
  </svg>
</button>

<%!-- Search input (shown when toggled) --%>
<div :if={@show_search} class="absolute top-16 right-4 z-50">
  <div class="card bg-base-100 shadow-xl w-80">
    <div class="card-body p-4">
      <input
        type="text"
        placeholder="Search messages..."
        value={@search_query}
        phx-change="search_messages"
        phx-debounce="300"
        name="query"
        class="input input-bordered w-full"
        autofocus
      />
      <div :if={@search_results != []} class="mt-2 max-h-60 overflow-y-auto">
        <div
          :for={msg <- @search_results}
          phx-click="jump_to_message"
          phx-value-message-id={msg.id}
          class="p-2 hover:bg-base-200 rounded cursor-pointer"
        >
          <div class="font-medium text-sm">{msg.sender.username}</div>
          <div class="text-sm truncate">{msg.content}</div>
          <div class="text-xs text-base-content/50">{format_time(msg.inserted_at)}</div>
        </div>
      </div>
      <p :if={@search_query != "" && @search_results == []} class="text-sm text-base-content/50 mt-2">
        No messages found
      </p>
    </div>
  </div>
</div>
```

### JavaScript Hook for Scrolling
```javascript
// In app.js
Hooks.ScrollToMessage = {
  mounted() {
    this.handleEvent("scroll_to_message", ({message_id}) => {
      const element = document.getElementById(`message-${message_id}`);
      if (element) {
        element.scrollIntoView({ behavior: "smooth", block: "center" });
        element.classList.add("highlight-message");
        setTimeout(() => element.classList.remove("highlight-message"), 2000);
      }
    });
  }
}
```

### CSS for Highlight Effect
```css
.highlight-message {
  animation: highlight-fade 2s ease-out;
}

@keyframes highlight-fade {
  0% { background-color: rgba(var(--p), 0.3); }
  100% { background-color: transparent; }
}
```

## Acceptance Criteria
- [ ] Search button appears in chat header
- [ ] Clicking search shows search input
- [ ] Typing in search shows matching messages
- [ ] Search is case-insensitive
- [ ] Clicking a result scrolls to that message
- [ ] Scrolled-to message is briefly highlighted
- [ ] "No results" shown when no matches
- [ ] Clear search resets state
- [ ] Search works in both direct and group chats
- [ ] Minimum 2 characters required for search

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Send several messages in a conversation
- Search for specific words and verify results
- Search for text that doesn't exist, verify "no results"
- Click on a search result and verify scroll behavior
- Test with special characters in search query
- Test search across multiple conversations
- Performance test with many messages (100+)

## Edge Cases to Handle
- Empty search query (don't search)
- Very short queries (minimum 2 characters)
- Special regex characters in query (escape them)
- HTML in messages (should not break search)
- Very long messages (truncate in results)
- User navigates away during search (cleanup)

---

## Completion Notes (Agent bf14801e)

### Implemented Features:
1. **Chat context `search_messages/2` function** - Added to `lib/elixirchat/chat.ex`:
   - Case-insensitive search using PostgreSQL ILIKE
   - Escapes special LIKE characters (%, _, \)
   - Returns up to 20 results ordered by most recent first
   - Preloads sender info
   - Requires minimum 2 character query

2. **ChatLive search functionality** - Updated `lib/elixirchat_web/live/chat_live.ex`:
   - Added `show_search`, `search_query`, `search_results` assigns
   - Added event handlers: `toggle_search`, `search_messages`, `clear_search`, `jump_to_message`
   - Search button in chat header
   - Search overlay with debounced input (300ms)
   - Results show sender, message content (truncated), and timestamp
   - "No results" and "minimum 2 chars" feedback messages

3. **Scroll-to-message functionality**:
   - Added message IDs to DOM elements (`message-#{id}`)
   - Extended ScrollToBottom hook to handle `scroll_to_message` events
   - Smooth scrolling with `scrollIntoView({ behavior: "smooth", block: "center" })`

4. **Visual highlight effect** - Added CSS in `assets/css/app.css`:
   - `.highlight-message` class with 2s fade animation
   - Uses theme primary color for highlight

5. **Tests** - Added 7 tests for `search_messages/2` in `test/elixirchat/chat_test.exs`:
   - Basic search functionality
   - Case insensitivity
   - Minimum query length
   - Result ordering
   - Result limit (20 max)
   - Special character escaping
   - Sender preloading

### Files Modified:
- `lib/elixirchat/chat.ex` - Added search_messages function
- `lib/elixirchat_web/live/chat_live.ex` - Added search UI and event handlers
- `assets/js/app.js` - Extended ScrollToBottom hook
- `assets/css/app.css` - Added highlight animation
- `test/elixirchat/chat_test.exs` - Added tests

### Not Implemented (future improvements):
- Text highlighting within search results (would require HTML escaping complexity)
- Database index on messages.content (performance optimization for large datasets)
- Full-text search using PostgreSQL tsvector (better search quality)

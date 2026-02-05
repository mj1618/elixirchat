# Task: Markdown Message Formatting

## Description
Add support for Markdown formatting in chat messages. Users can use standard Markdown syntax to format their messages with bold, italic, code blocks, inline code, links, and strikethrough. This is essential for technical discussions and makes conversations more expressive and readable.

## Requirements
- Support basic Markdown formatting:
  - **Bold** with `**text**` or `__text__`
  - *Italic* with `*text*` or `_text_`
  - ~~Strikethrough~~ with `~~text~~`
  - `Inline code` with backticks
  - Code blocks with triple backticks (with optional language syntax highlighting)
  - [Links](url) with `[text](url)`
  - Automatic URL detection and linking
- Render formatted messages in the chat
- Preserve formatting in message search results
- Formatting works alongside existing mentions (@username)
- Raw Markdown visible when editing a message
- XSS protection - sanitize HTML to prevent injection attacks

## Implementation Steps

1. **Add Markdown parsing dependency**:
   - Add `earmark` to mix.exs for Markdown parsing
   - Add `html_sanitize_ex` for sanitization (or use Phoenix.HTML.sanitize)

2. **Create Markdown formatter module** (`lib/elixirchat/chat/markdown.ex`):
   - `render/1` - Convert Markdown to safe HTML
   - Configure Earmark options (disable raw HTML, etc.)
   - Apply HTML sanitization to output
   - Handle edge cases (empty strings, nil, etc.)

3. **Update message rendering in ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Apply Markdown formatting after mention rendering
   - Use `raw/1` to render HTML safely
   - Ensure proper CSS for code blocks, links, etc.

4. **Add CSS styles for Markdown elements** (`assets/css/app.css`):
   - Style code blocks with background color, monospace font
   - Style inline code with subtle background
   - Style links appropriately
   - Style strikethrough text
   - Ensure styles work in both light and dark themes

5. **Update message search to handle Markdown**:
   - Search should match raw text, not rendered HTML
   - Display search results with plain text preview

6. **Add syntax highlighting for code blocks** (optional):
   - Use a client-side highlighter (e.g., highlight.js via CDN)
   - Support common languages: elixir, javascript, python, bash, json, etc.

## Technical Details

### Dependencies
```elixir
# mix.exs
defp deps do
  [
    # ... existing deps ...
    {:earmark, "~> 1.4"},
    {:html_sanitize_ex, "~> 1.4"}
  ]
end
```

### Markdown Module
```elixir
defmodule Elixirchat.Chat.Markdown do
  @moduledoc """
  Renders Markdown content to safe HTML for display in chat messages.
  """

  @earmark_options %Earmark.Options{
    code_class_prefix: "language-",
    smartypants: false,
    breaks: true  # Convert single newlines to <br>
  }

  @allowed_tags ~w(p br strong em del code pre a ul ol li)
  @allowed_attributes ["href", "class", "target", "rel"]

  def render(nil), do: ""
  def render(""), do: ""
  def render(text) when is_binary(text) do
    text
    |> Earmark.as_html!(@earmark_options)
    |> HtmlSanitizeEx.basic_html()
    |> make_links_safe()
  end

  # Add target="_blank" and rel="noopener" to links
  defp make_links_safe(html) do
    html
    |> String.replace(~r/<a href="([^"]+)"/, ~s(<a href="\\1" target="_blank" rel="noopener noreferrer"))
  end
end
```

### Integration with Mentions
The message rendering order should be:
1. Parse mentions (@username) and wrap them
2. Apply Markdown formatting
3. Render as safe HTML

```elixir
# In chat_live.ex render function
<span class="message-content">
  <%= raw(format_message_content(message.content, @conversation.id)) %>
</span>

# Helper function
defp format_message_content(content, conversation_id) do
  content
  |> Mentions.render_with_mentions(conversation_id)
  |> Markdown.render()
end
```

### CSS Styles
```css
/* Message markdown styles */
.chat-bubble code {
  @apply bg-base-300 px-1 py-0.5 rounded text-sm font-mono;
}

.chat-bubble pre {
  @apply bg-base-300 p-3 rounded-lg my-2 overflow-x-auto;
}

.chat-bubble pre code {
  @apply bg-transparent p-0;
}

.chat-bubble a {
  @apply text-primary underline hover:text-primary-focus;
}

.chat-bubble strong {
  @apply font-bold;
}

.chat-bubble em {
  @apply italic;
}

.chat-bubble del {
  @apply line-through opacity-70;
}

.chat-bubble ul, .chat-bubble ol {
  @apply ml-4 my-1;
}

.chat-bubble ul {
  @apply list-disc;
}

.chat-bubble ol {
  @apply list-decimal;
}

.chat-bubble li {
  @apply my-0.5;
}
```

### Syntax Highlighting (Optional)
```heex
<%!-- In layouts/root.html.heex or app.html.heex --%>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" />
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script>
  // Highlight code blocks on page load and LiveView updates
  document.addEventListener("DOMContentLoaded", () => hljs.highlightAll());
  window.addEventListener("phx:page-loading-stop", () => hljs.highlightAll());
</script>
```

### XSS Protection Examples
The sanitizer should strip:
- `<script>` tags
- Event handlers (onclick, onerror, etc.)
- javascript: URLs
- data: URLs in images
- Custom HTML tags

Test cases:
```
Input: <script>alert('xss')</script>
Output: (stripped)

Input: [Click me](javascript:alert('xss'))
Output: [Click me](#) or stripped

Input: **bold** and <b>also bold</b>
Output: <strong>bold</strong> and also bold
```

## Acceptance Criteria
- [ ] **Bold** text renders correctly with `**text**`
- [ ] *Italic* text renders correctly with `*text*` or `_text_`
- [ ] ~~Strikethrough~~ renders correctly with `~~text~~`
- [ ] `Inline code` renders with backticks
- [ ] Code blocks render with triple backticks
- [ ] Language-specific syntax highlighting in code blocks
- [ ] Links render and open in new tab
- [ ] Plain URLs auto-link
- [ ] @mentions still work within formatted text
- [ ] No XSS vulnerabilities (test with script tags, event handlers)
- [ ] Editing shows raw Markdown, not rendered HTML
- [ ] Message search works on raw text content
- [ ] Formatting works in both direct and group chats
- [ ] Proper styling in both light/dark themes (if themes exist)

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)
- Task 015: User Mentions (completed) - need to integrate with mentions

## Testing Notes
- Send a message with bold text: `**hello world**`
- Send a message with code block:
  ```
  ```elixir
  IO.puts("Hello")
  ```
  ```
- Send a message with inline code: `use `backticks` for code`
- Send a message with a link: `Check out [this](https://example.com)`
- Try XSS attack: `<script>alert('xss')</script>`
- Try mixing mentions and formatting: `**@username** check this out`
- Edit a formatted message and verify raw Markdown is shown
- Search for text within a formatted message

## Edge Cases to Handle
- Unmatched formatting markers (e.g., single `*`)
- Very long code blocks (scrollable, not breaking layout)
- Nested formatting (bold within italic)
- Formatting across multiple lines
- Empty code blocks
- Code blocks with unsupported/unknown language
- Mentions inside code blocks (should NOT highlight as mentions)
- URLs inside code blocks (should NOT auto-link)
- Very long URLs (truncate display but keep full href)
- Mixed Markdown and raw HTML (strip HTML, keep Markdown)

## Future Enhancements (not in this task)
- Tables support
- Block quotes
- Task lists (checkboxes)
- Emoji shortcodes (:smile: -> 😊)
- Keyboard shortcuts for formatting (Ctrl+B for bold)
- Formatting toolbar/buttons for non-technical users
- LaTeX/math equation support

---

## Completion Notes (Agent d12ce640)

### Completed on: 2026-02-05

### Implementation Summary:

1. **Added earmark dependency** to `mix.exs`
   - Version ~> 1.4 for Markdown parsing

2. **Created Markdown module** (`lib/elixirchat/chat/markdown.ex`)
   - `render/1` - Converts Markdown to safe HTML
   - `render_with_mentions/2` - Renders Markdown with mention highlighting, skipping mentions inside code blocks
   - Custom HTML sanitization that strips dangerous tags (script, style, event handlers)
   - Automatically adds `target="_blank"` and `rel="noopener noreferrer"` to external links
   - Supports: bold, italic, strikethrough, inline code, code blocks, links, auto-linking URLs, lists

3. **Updated ChatLive** (`lib/elixirchat_web/live/chat_live.ex`)
   - Added `Markdown` alias
   - Created `format_message_content/2` helper function that combines Markdown rendering with mentions
   - Updated message content rendering to use the new helper with `markdown-content` CSS class

4. **Added CSS styles** (`assets/css/app.css`)
   - Styled inline code with monospace font and subtle background
   - Styled code blocks with padding, border-radius, and overflow handling
   - Styled links with primary color and underline
   - Styled bold, italic, strikethrough, and lists appropriately

### Testing Notes:
- Tested **bold**, *italic*, ~~strikethrough~~, and `inline code` - all render correctly
- Tested links - renders as clickable, opens in new tab
- Tested code blocks - renders with monospace font
- Tested XSS prevention - script tags are stripped
- Mentions still work and are properly highlighted
- Mentions inside code blocks are NOT highlighted (as intended)

### Not Implemented (out of scope):
- Syntax highlighting for code blocks (would require external JS library)
- Tables, blockquotes, task lists

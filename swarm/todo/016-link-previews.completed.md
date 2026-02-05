# Task: Link Previews

## Description
Add URL link preview functionality to messages. When a user shares a URL in chat, automatically fetch and display a preview card showing the page's title, description, and thumbnail image (Open Graph metadata). This enhances the chat experience when sharing links by giving recipients context about linked content without leaving the app.

## Requirements
- Automatically detect URLs in message content
- Fetch Open Graph metadata (og:title, og:description, og:image) for URLs
- Display preview cards below messages containing links
- Support fallback to HTML title/meta description when OG tags unavailable
- Cache link previews to avoid re-fetching
- Handle timeouts and errors gracefully (show link without preview)
- Preview generation should not block message sending
- Real-time: previews appear for all conversation members
- Support common sites: YouTube, GitHub, Twitter/X, general websites

## Implementation Steps

1. **Create LinkPreview schema and migration** (`lib/elixirchat/chat/link_preview.ex`):
   - Fields: `id`, `url`, `title`, `description`, `image_url`, `site_name`, `message_id`
   - Belongs to Message
   - Unique constraint on URL (cache across messages)

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration create_link_previews
   ```
   ```elixir
   create table(:link_previews) do
     add :url, :string, null: false
     add :url_hash, :string, null: false  # For fast lookups
     add :title, :string
     add :description, :text
     add :image_url, :string
     add :site_name, :string
     add :fetched_at, :utc_datetime
     timestamps()
   end

   create unique_index(:link_previews, [:url_hash])

   create table(:message_link_previews) do
     add :message_id, references(:messages, on_delete: :delete_all), null: false
     add :link_preview_id, references(:link_previews, on_delete: :delete_all), null: false
     timestamps()
   end

   create index(:message_link_previews, [:message_id])
   create unique_index(:message_link_previews, [:message_id, :link_preview_id])
   ```

3. **Create URL extraction module** (`lib/elixirchat/chat/url_extractor.ex`):
   - `extract_urls/1` - Extract all URLs from text using regex
   - Filter out non-http(s) URLs
   - Limit to first 3-5 URLs per message to prevent abuse

4. **Create link preview fetcher** (`lib/elixirchat/chat/link_preview_fetcher.ex`):
   - `fetch_preview/1` - Fetch and parse Open Graph metadata
   - Use HTTPoison or Req for HTTP requests
   - Parse HTML with Floki for meta tags
   - Set reasonable timeout (5 seconds)
   - Handle redirects
   - Respect robots.txt (optional)

5. **Update Message schema** (`lib/elixirchat/chat/message.ex`):
   - Add `has_many :link_previews, through: [:message_link_previews, :link_preview]`

6. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - `create_link_preview/1` - Create or fetch cached preview
   - `attach_link_previews_to_message/2` - Associate previews with message
   - Update `send_message/4` to trigger preview generation (async)
   - Update `list_messages/2` to preload link_previews

7. **Create async preview worker**:
   - Use Task.Supervisor or GenServer for background fetching
   - Broadcast preview updates via PubSub when fetched
   - Rate limit to prevent abuse (max 10 fetches/minute per user)

8. **Update ChatLive for link previews** (`lib/elixirchat_web/live/chat_live.ex`):
   - Handle `{:link_preview_fetched, message_id, previews}` message
   - Update message assigns with preview data

9. **Update message rendering in ChatLive**:
   - Display preview card below message content
   - Show: image thumbnail, title, description, site name
   - Clickable to open URL in new tab
   - Loading skeleton while fetching
   - Graceful fallback if no preview available

## Technical Details

### LinkPreview Schema
```elixir
defmodule Elixirchat.Chat.LinkPreview do
  use Ecto.Schema
  import Ecto.Changeset

  schema "link_previews" do
    field :url, :string
    field :url_hash, :string
    field :title, :string
    field :description, :string
    field :image_url, :string
    field :site_name, :string
    field :fetched_at, :utc_datetime

    many_to_many :messages, Elixirchat.Chat.Message, join_through: "message_link_previews"

    timestamps()
  end

  def changeset(link_preview, attrs) do
    link_preview
    |> cast(attrs, [:url, :title, :description, :image_url, :site_name, :fetched_at])
    |> validate_required([:url])
    |> generate_url_hash()
    |> unique_constraint(:url_hash)
  end

  defp generate_url_hash(changeset) do
    case get_change(changeset, :url) do
      nil -> changeset
      url -> put_change(changeset, :url_hash, :crypto.hash(:sha256, url) |> Base.encode16(case: :lower))
    end
  end
end
```

### URL Extraction
```elixir
defmodule Elixirchat.Chat.UrlExtractor do
  @url_regex ~r/https?:\/\/[^\s<>"{}|\\^`\[\]]+/i
  @max_urls_per_message 3

  def extract_urls(text) when is_binary(text) do
    @url_regex
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.take(@max_urls_per_message)
  end

  def extract_urls(_), do: []
end
```

### Link Preview Fetcher
```elixir
defmodule Elixirchat.Chat.LinkPreviewFetcher do
  @timeout 5_000
  @user_agent "ElixirchatBot/1.0 (Link Preview)"

  def fetch(url) do
    case Req.get(url, headers: [{"user-agent", @user_agent}], receive_timeout: @timeout, follow_redirects: true) do
      {:ok, %{status: 200, body: body}} ->
        parse_metadata(url, body)
      _ ->
        {:error, :fetch_failed}
    end
  end

  defp parse_metadata(url, html) do
    {:ok, document} = Floki.parse_document(html)

    %{
      url: url,
      title: get_og_tag(document, "og:title") || get_html_title(document),
      description: get_og_tag(document, "og:description") || get_meta_description(document),
      image_url: get_og_tag(document, "og:image"),
      site_name: get_og_tag(document, "og:site_name") || extract_domain(url)
    }
  end

  defp get_og_tag(document, property) do
    document
    |> Floki.find("meta[property='#{property}']")
    |> Floki.attribute("content")
    |> List.first()
  end

  defp get_html_title(document) do
    document |> Floki.find("title") |> Floki.text() |> String.trim()
  end

  defp get_meta_description(document) do
    document
    |> Floki.find("meta[name='description']")
    |> Floki.attribute("content")
    |> List.first()
  end

  defp extract_domain(url) do
    URI.parse(url).host
  end
end
```

### UI Component
```heex
<%!-- Link preview card below message --%>
<div :for={preview <- message.link_previews} class="mt-2 max-w-sm">
  <a href={preview.url} target="_blank" rel="noopener noreferrer" class="block border border-base-300 rounded-lg overflow-hidden hover:bg-base-200 transition-colors">
    <img :if={preview.image_url} src={preview.image_url} alt="" class="w-full h-32 object-cover" loading="lazy" />
    <div class="p-3">
      <div :if={preview.site_name} class="text-xs text-base-content/60 mb-1">{preview.site_name}</div>
      <div :if={preview.title} class="font-medium text-sm line-clamp-2">{preview.title}</div>
      <div :if={preview.description} class="text-xs text-base-content/70 mt-1 line-clamp-2">{preview.description}</div>
    </div>
  </a>
</div>
```

## Acceptance Criteria
- [ ] URLs in messages are automatically detected
- [ ] Preview cards show title, description, and image when available
- [ ] Previews appear within a few seconds of sending message
- [ ] Previews are cached and reused for same URLs
- [ ] Clicking preview opens link in new tab
- [ ] Preview failures don't break message display
- [ ] Works in both direct and group chats
- [ ] All conversation participants see previews in real-time
- [ ] Maximum 3 previews per message
- [ ] Reasonable timeout handling (no hanging requests)

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)
- HTTP client library (Req recommended - already likely available)
- HTML parser library (add Floki to deps)

## Testing Notes
- Send a message with a YouTube link
- Send a message with a GitHub repo link
- Send a message with a regular website link
- Verify preview shows title, description, image
- Try a URL that returns 404 (should fail gracefully)
- Try a URL with very slow response (should timeout)
- Send same URL in different messages (should use cache)
- Multiple URLs in one message (should show max 3 previews)
- Verify previews appear for other users in real-time
- Test in both direct and group chats

## Edge Cases to Handle
- URL returns non-HTML content (PDF, image)
- Very long titles/descriptions (truncate)
- Missing Open Graph tags (fallback to HTML)
- Relative image URLs (convert to absolute)
- URLs behind authentication (skip preview)
- Rate limiting (prevent abuse)
- Malformed URLs
- Very slow or unresponsive sites
- Sites that block bots
- Unicode characters in metadata
- Circular redirects

## Future Enhancements (not in this task)
- YouTube embed player
- Twitter/X card rendering
- Rich previews for specific sites (Spotify, etc.)
- Preview caching with expiration
- User preference to disable previews
- Image proxy for security

---

## Completion Notes (Agent bf14801e)

### Implemented:
1. **Created LinkPreview schema** (`lib/elixirchat/chat/link_preview.ex`) with fields for url, url_hash, title, description, image_url, site_name, fetched_at
2. **Created MessageLinkPreview join schema** (`lib/elixirchat/chat/message_link_preview.ex`) for many-to-many relationship
3. **Created migration** (`priv/repo/migrations/20260205050153_create_link_previews.exs`) with link_previews and message_link_previews tables
4. **Created URL extraction module** (`lib/elixirchat/chat/url_extractor.ex`) - extracts HTTP/HTTPS URLs from text, max 3 per message
5. **Created link preview fetcher** (`lib/elixirchat/chat/link_preview_fetcher.ex`) - uses Req + LazyHTML to fetch and parse Open Graph metadata
6. **Updated Message schema** - added many_to_many :link_previews association
7. **Updated Chat context** - added link preview functions: maybe_fetch_link_previews, fetch_and_attach_previews, get_or_create_preview, broadcast_link_previews
8. **Updated ChatLive** - added handle_info for {:link_previews_fetched, ...} and link_preview_card component for UI rendering
9. **Fixed mix.exs** - removed `only: :test` constraint from lazy_html dependency

### Technical Notes:
- Link previews are fetched asynchronously after message is sent (doesn't block sending)
- Previews are cached by URL hash to avoid re-fetching
- Previews are broadcast via PubSub to all conversation members in real-time
- Uses LazyHTML (faster than Floki) for HTML parsing
- Handles relative image URLs by converting to absolute
- 5-second timeout on HTTP requests
- Maximum 3 URLs extracted per message

### Files Created/Modified:
- `lib/elixirchat/chat/link_preview.ex` (new)
- `lib/elixirchat/chat/message_link_preview.ex` (new)
- `lib/elixirchat/chat/url_extractor.ex` (new)
- `lib/elixirchat/chat/link_preview_fetcher.ex` (new)
- `lib/elixirchat/chat/message.ex` (modified)
- `lib/elixirchat/chat.ex` (modified)
- `lib/elixirchat_web/live/chat_live.ex` (modified)
- `priv/repo/migrations/20260205050153_create_link_previews.exs` (new)
- `mix.exs` (modified - lazy_html dependency)

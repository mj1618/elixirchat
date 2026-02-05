defmodule Elixirchat.Chat.Markdown do
  @moduledoc """
  Renders Markdown content to safe HTML for display in chat messages.
  
  Supports:
  - Bold (**text** or __text__)
  - Italic (*text* or _text_)
  - Strikethrough (~~text~~)
  - Inline code (`code`)
  - Code blocks (```language ... ```)
  - Links ([text](url))
  - Automatic URL detection
  - Lists (ordered and unordered)
  
  All output is sanitized to prevent XSS attacks.
  """

  @earmark_options %Earmark.Options{
    code_class_prefix: "language-",
    smartypants: false,
    breaks: true,  # Convert single newlines to <br>
    pure_links: true  # Auto-link bare URLs
  }

  # Tags allowed in the output HTML
  @allowed_tags ~w(p br strong em del code pre a ul ol li span)

  # Attributes allowed on tags
  @allowed_attributes %{
    "a" => ["href", "target", "rel"],
    "code" => ["class"],
    "pre" => ["class"],
    "span" => ["class", "data-username"]
  }

  @mention_regex ~r/@([a-zA-Z0-9_]+)/

  @doc """
  Renders markdown text to safe HTML.
  
  Returns an HTML string that can be used with Phoenix's `raw/1` helper.
  All HTML is sanitized to prevent XSS attacks.
  
  ## Examples
  
      iex> Markdown.render("**bold** and *italic*")
      "<p><strong>bold</strong> and <em>italic</em></p>"
      
      iex> Markdown.render("<script>alert('xss')</script>")
      "<p></p>"
  """
  @spec render(String.t() | nil) :: String.t()
  def render(nil), do: ""
  def render(""), do: ""
  
  def render(text) when is_binary(text) do
    text
    |> Earmark.as_html!(@earmark_options)
    |> sanitize_html()
    |> make_links_safe()
  end

  @doc """
  Renders markdown with mentions support.
  
  Takes a MapSet of valid usernames (lowercase) and will highlight
  @mentions for those users, but NOT inside code blocks.
  
  ## Examples
  
      iex> valid_users = MapSet.new(["john", "jane"])
      iex> Markdown.render_with_mentions("Hello @john!", valid_users)
      "<p>Hello <span class=\"mention text-primary font-semibold\" data-username=\"john\">@john</span>!</p>"
  """
  @spec render_with_mentions(String.t() | nil, MapSet.t()) :: String.t()
  def render_with_mentions(nil, _valid_usernames), do: ""
  def render_with_mentions("", _valid_usernames), do: ""
  
  def render_with_mentions(text, valid_usernames) when is_binary(text) do
    text
    |> Earmark.as_html!(@earmark_options)
    |> sanitize_html()
    |> make_links_safe()
    |> apply_mentions(valid_usernames)
  end

  @doc """
  Checks if text contains any markdown formatting.
  Useful for determining if markdown rendering is needed.
  """
  @spec has_markdown?(String.t()) :: boolean()
  def has_markdown?(text) when is_binary(text) do
    # Check for common markdown patterns
    Regex.match?(~r/(\*\*|__|~~|`|^\s*[-*+]\s|^\s*\d+\.\s|\[.+\]\(.+\))/m, text)
  end
  
  def has_markdown?(_), do: false

  # Apply mention highlighting, skipping content inside code/pre tags
  defp apply_mentions(html, valid_usernames) do
    # Split HTML into segments: code blocks, inline code, and regular text
    # We'll only apply mentions to regular text segments
    
    # Pattern to match code blocks and inline code
    code_pattern = ~r/(<pre[^>]*>.*?<\/pre>|<code[^>]*>.*?<\/code>)/s
    
    # Split by code blocks, keeping the delimiters
    parts = Regex.split(code_pattern, html, include_captures: true)
    
    parts
    |> Enum.map(fn part ->
      if Regex.match?(~r/^<(pre|code)/i, part) do
        # This is a code block, leave it unchanged
        part
      else
        # This is regular text, apply mentions
        apply_mentions_to_text(part, valid_usernames)
      end
    end)
    |> Enum.join()
  end

  defp apply_mentions_to_text(text, valid_usernames) do
    Regex.replace(@mention_regex, text, fn full, username ->
      if MapSet.member?(valid_usernames, String.downcase(username)) do
        escaped_username = Phoenix.HTML.html_escape(username) |> Phoenix.HTML.safe_to_string()
        escaped_full = Phoenix.HTML.html_escape(full) |> Phoenix.HTML.safe_to_string()
        ~s(<span class="mention text-primary font-semibold" data-username="#{escaped_username}">#{escaped_full}</span>)
      else
        full
      end
    end)
  end

  # Sanitize HTML to remove dangerous tags and attributes
  defp sanitize_html(html) do
    html
    |> remove_dangerous_tags()
    |> sanitize_attributes()
  end

  # Remove script, style, and other dangerous tags
  defp remove_dangerous_tags(html) do
    # Remove script tags and their contents
    html = Regex.replace(~r/<script\b[^>]*>.*?<\/script>/is, html, "")
    
    # Remove style tags and their contents
    html = Regex.replace(~r/<style\b[^>]*>.*?<\/style>/is, html, "")
    
    # Remove event handlers (onclick, onerror, etc.)
    html = Regex.replace(~r/\s+on\w+\s*=\s*["'][^"']*["']/i, html, "")
    html = Regex.replace(~r/\s+on\w+\s*=\s*[^\s>]+/i, html, "")
    
    # Remove javascript: URLs
    html = Regex.replace(~r/href\s*=\s*["']javascript:[^"']*["']/i, html, ~s(href="#"))
    
    # Remove data: URLs in src attributes (but allow in href for downloads if needed)
    html = Regex.replace(~r/src\s*=\s*["']data:[^"']*["']/i, html, ~s(src=""))
    
    # Remove tags that aren't in our allowed list
    html = Regex.replace(~r/<(\/?)((?!#{allowed_tags_pattern()})[a-z][a-z0-9]*)\b[^>]*>/i, html, "")
    
    html
  end

  defp allowed_tags_pattern do
    @allowed_tags |> Enum.join("|")
  end

  # Sanitize attributes on allowed tags
  defp sanitize_attributes(html) do
    # Process each allowed tag and keep only allowed attributes
    Enum.reduce(@allowed_attributes, html, fn {tag, allowed_attrs}, acc ->
      # Match opening tags and filter their attributes
      Regex.replace(
        ~r/<#{tag}\b([^>]*)>/i,
        acc,
        fn _, attrs ->
          clean_attrs = filter_attributes(attrs, allowed_attrs)
          if clean_attrs == "" do
            "<#{tag}>"
          else
            "<#{tag} #{clean_attrs}>"
          end
        end
      )
    end)
  end

  # Filter attributes to only keep allowed ones
  defp filter_attributes(attrs_string, allowed_attrs) do
    # Extract attribute pairs
    Regex.scan(~r/(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i, attrs_string)
    |> Enum.filter(fn [_, attr_name | _] ->
      String.downcase(attr_name) in allowed_attrs
    end)
    |> Enum.map(fn [full_match | _] -> full_match end)
    |> Enum.join(" ")
  end

  # Add security attributes to links
  defp make_links_safe(html) do
    # Add target="_blank" and rel="noopener noreferrer" to external links
    Regex.replace(
      ~r/<a\s+href="(https?:\/\/[^"]+)"([^>]*)>/i,
      html,
      fn _, href, rest_attrs ->
        # Only add if not already present
        attrs = rest_attrs
        attrs = if String.contains?(attrs, "target="), do: attrs, else: attrs <> ~s( target="_blank")
        attrs = if String.contains?(attrs, "rel="), do: attrs, else: attrs <> ~s( rel="noopener noreferrer")
        ~s(<a href="#{href}"#{attrs}>)
      end
    )
  end
end

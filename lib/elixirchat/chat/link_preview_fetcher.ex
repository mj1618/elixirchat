defmodule Elixirchat.Chat.LinkPreviewFetcher do
  @moduledoc """
  Fetches Open Graph and HTML metadata from URLs for link previews.
  """

  @timeout 5_000
  @user_agent "ElixirchatBot/1.0 (Link Preview)"

  @doc """
  Fetches metadata from a URL and returns preview data.

  Returns {:ok, map} on success or {:error, reason} on failure.
  The map contains: url, title, description, image_url, site_name
  """
  def fetch(url) do
    case Req.get(url,
           headers: [{"user-agent", @user_agent}],
           receive_timeout: @timeout,
           max_redirects: 5
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        parse_metadata(url, body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  end

  defp parse_metadata(url, html) do
    # Parse the HTML document
    lazy_html = LazyHTML.from_document(html)

    metadata = %{
      url: url,
      title: get_og_tag(lazy_html, "og:title") || get_html_title(lazy_html),
      description: get_og_tag(lazy_html, "og:description") || get_meta_description(lazy_html),
      image_url: get_og_tag(lazy_html, "og:image") |> maybe_make_absolute(url),
      site_name: get_og_tag(lazy_html, "og:site_name") || extract_domain(url),
      fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:ok, metadata}
  end

  defp get_og_tag(lazy_html, property) do
    # Try meta[property="og:..."] first (standard), then meta[name="og:..."] (fallback)
    result =
      lazy_html
      |> LazyHTML.query("meta[property='#{property}']")
      |> LazyHTML.attribute("content")
      |> List.first()

    if result do
      result
    else
      lazy_html
      |> LazyHTML.query("meta[name='#{property}']")
      |> LazyHTML.attribute("content")
      |> List.first()
    end
  end

  defp get_html_title(lazy_html) do
    lazy_html
    |> LazyHTML.query("title")
    |> LazyHTML.text()
    |> String.trim()
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp get_meta_description(lazy_html) do
    lazy_html
    |> LazyHTML.query("meta[name='description']")
    |> LazyHTML.attribute("content")
    |> List.first()
  end

  defp extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host
        |> String.replace_prefix("www.", "")

      _ ->
        nil
    end
  end

  # Convert relative image URLs to absolute
  defp maybe_make_absolute(nil, _base_url), do: nil
  defp maybe_make_absolute("", _base_url), do: nil

  defp maybe_make_absolute(image_url, base_url) do
    base_uri = URI.parse(base_url)
    image_uri = URI.parse(image_url)

    cond do
      # Already absolute
      image_uri.scheme != nil ->
        image_url

      # Protocol-relative URL (//example.com/image.png)
      String.starts_with?(image_url, "//") ->
        "#{base_uri.scheme}:#{image_url}"

      # Root-relative URL (/images/foo.png)
      String.starts_with?(image_url, "/") ->
        "#{base_uri.scheme}://#{base_uri.host}#{image_url}"

      # Relative URL (images/foo.png)
      true ->
        base_path = base_uri.path || "/"
        dir = Path.dirname(base_path)
        "#{base_uri.scheme}://#{base_uri.host}#{Path.join(dir, image_url)}"
    end
  end
end

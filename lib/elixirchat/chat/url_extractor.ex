defmodule Elixirchat.Chat.UrlExtractor do
  @moduledoc """
  Extracts URLs from message content.
  """

  # Match http:// or https:// URLs, stopping at whitespace or common delimiters
  @url_regex ~r/https?:\/\/[^\s<>"{}|\\^`\[\]]+/i
  @max_urls_per_message 3

  @doc """
  Extracts all valid HTTP/HTTPS URLs from text.
  Returns a list of unique URLs, limited to #{@max_urls_per_message} URLs per message.

  ## Examples

      iex> UrlExtractor.extract_urls("Check out https://example.com")
      ["https://example.com"]

      iex> UrlExtractor.extract_urls("Visit https://foo.com and https://bar.com")
      ["https://foo.com", "https://bar.com"]

  """
  def extract_urls(text) when is_binary(text) do
    @url_regex
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.map(&clean_url/1)
    |> Enum.uniq()
    |> Enum.take(@max_urls_per_message)
  end

  def extract_urls(_), do: []

  # Clean trailing punctuation that might have been captured
  defp clean_url(url) do
    url
    |> String.trim_trailing(".")
    |> String.trim_trailing(",")
    |> String.trim_trailing(")")
    |> String.trim_trailing(";")
    |> String.trim_trailing(":")
  end

  @doc """
  Returns the maximum number of URLs allowed per message.
  """
  def max_urls_per_message, do: @max_urls_per_message
end

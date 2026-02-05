defmodule Elixirchat.Agent.WebSearch do
  @moduledoc """
  Module for performing web searches using Tavily's AI-optimized search API.
  Tavily is specifically designed for AI agents and returns LLM-ready results.
  """

  require Logger

  @api_url "https://api.tavily.com/search"
  @timeout 15_000

  @doc """
  Performs a web search using Tavily's search API.

  Returns `{:ok, results_text}` or `{:error, reason}`.

  ## Examples

      iex> WebSearch.search("Elixir programming language")
      {:ok, "Elixir is a functional, concurrent programming language..."}

  """
  def search(query) when is_binary(query) and byte_size(query) > 0 do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.warning("Tavily API key not configured, web search unavailable")
      {:error, :api_key_missing}
    else
      body = %{
        query: query,
        search_depth: "basic",
        include_answer: true,
        max_results: 5
      }

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(@api_url, json: body, headers: headers, receive_timeout: @timeout) do
        {:ok, %{status: 200, body: response}} when is_map(response) ->
          {:ok, format_results(query, response)}

        {:ok, %{status: 401}} ->
          Logger.error("Tavily API: Invalid API key")
          {:error, :invalid_api_key}

        {:ok, %{status: 429}} ->
          Logger.warning("Tavily API: Rate limited")
          {:error, :rate_limited}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Tavily API error: status=#{status}, body=#{inspect(body)}")
          {:error, {:api_error, status}}

        {:error, reason} ->
          Logger.error("Tavily API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  def search(_), do: {:error, :invalid_query}

  @doc """
  Formats the Tavily API response into readable text for the LLM.
  """
  def format_results(query, response) do
    parts = []

    # Add the AI-generated answer if available (most valuable part)
    parts =
      case Map.get(response, "answer") do
        answer when is_binary(answer) and byte_size(answer) > 0 ->
          ["## Summary\n#{answer}" | parts]

        _ ->
          parts
      end

    # Add individual search results
    parts =
      case Map.get(response, "results", []) do
        results when is_list(results) and length(results) > 0 ->
          formatted_results =
            results
            |> Enum.take(5)
            |> Enum.map(&format_result/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.join("\n\n")

          if formatted_results != "" do
            ["## Sources\n#{formatted_results}" | parts]
          else
            parts
          end

        _ ->
          parts
      end

    result = parts |> Enum.reverse() |> Enum.join("\n\n")

    if result == "" do
      "No search results found for '#{query}'. Try rephrasing your query or searching for something more specific."
    else
      result
    end
  end

  defp format_result(%{"title" => title, "url" => url, "content" => content})
       when is_binary(title) and is_binary(url) and is_binary(content) do
    # Truncate content if too long
    truncated_content =
      if String.length(content) > 500 do
        String.slice(content, 0, 500) <> "..."
      else
        content
      end

    "**#{title}**\n#{truncated_content}\nSource: #{url}"
  end

  defp format_result(%{"title" => title, "url" => url}) when is_binary(title) and is_binary(url) do
    "**#{title}**\nSource: #{url}"
  end

  defp format_result(_), do: nil

  defp get_api_key do
    Application.get_env(:elixirchat, :tavily)[:api_key] ||
      System.get_env("TAVILY_API_KEY")
  end
end

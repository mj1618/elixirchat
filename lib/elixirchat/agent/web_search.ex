defmodule Elixirchat.Agent.WebSearch do
  @moduledoc """
  Module for performing web searches using DuckDuckGo's instant answer API.
  """

  require Logger

  @api_url "https://api.duckduckgo.com/"
  @timeout 10_000

  @doc """
  Performs a web search using DuckDuckGo's instant answer API.

  Returns `{:ok, results_text}` or `{:error, reason}`.

  ## Examples

      iex> WebSearch.search("Elixir programming language")
      {:ok, "Elixir is a functional, concurrent programming language..."}

  """
  def search(query) when is_binary(query) and byte_size(query) > 0 do
    params = [
      q: query,
      format: "json",
      no_html: "1",
      skip_disambig: "1"
    ]

    url = "#{@api_url}?#{URI.encode_query(params)}"

    case Req.get(url, receive_timeout: @timeout) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, format_results(query, body)}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        # Try to decode if body is still a string
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, format_results(query, decoded)}
          {:error, _} -> {:error, :invalid_response}
        end

      {:ok, %{status: status}} ->
        Logger.error("DuckDuckGo API error: status=#{status}")
        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.error("DuckDuckGo API request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  def search(_), do: {:error, :invalid_query}

  @doc """
  Formats the DuckDuckGo API response into readable text.
  """
  def format_results(query, response) do
    parts = []

    # Add the abstract (main answer)
    parts =
      case Map.get(response, "Abstract", "") do
        abstract when is_binary(abstract) and byte_size(abstract) > 0 ->
          source = Map.get(response, "AbstractSource", "")
          url = Map.get(response, "AbstractURL", "")

          abstract_text =
            if source != "" and url != "" do
              "#{abstract}\n(Source: #{source} - #{url})"
            else
              abstract
            end

          [abstract_text | parts]

        _ ->
          parts
      end

    # Add instant answer if available
    parts =
      case Map.get(response, "Answer", "") do
        answer when is_binary(answer) and byte_size(answer) > 0 ->
          ["Answer: #{answer}" | parts]

        _ ->
          parts
      end

    # Add definition if available
    parts =
      case Map.get(response, "Definition", "") do
        definition when is_binary(definition) and byte_size(definition) > 0 ->
          source = Map.get(response, "DefinitionSource", "")

          def_text =
            if source != "" do
              "Definition: #{definition} (#{source})"
            else
              "Definition: #{definition}"
            end

          [def_text | parts]

        _ ->
          parts
      end

    # Add related topics (limit to top 5)
    parts =
      case Map.get(response, "RelatedTopics", []) do
        topics when is_list(topics) and length(topics) > 0 ->
          related =
            topics
            |> Enum.take(5)
            |> Enum.map(&extract_topic_text/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.join("\n- ")

          if related != "" do
            ["Related:\n- #{related}" | parts]
          else
            parts
          end

        _ ->
          parts
      end

    # Add infobox data if available
    parts =
      case Map.get(response, "Infobox") do
        %{"content" => content} when is_list(content) and length(content) > 0 ->
          info =
            content
            |> Enum.take(5)
            |> Enum.map(fn
              %{"label" => label, "value" => value} -> "#{label}: #{value}"
              _ -> nil
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.join("\n")

          if info != "" do
            ["Info:\n#{info}" | parts]
          else
            parts
          end

        _ ->
          parts
      end

    result = parts |> Enum.reverse() |> Enum.join("\n\n")

    if result == "" do
      "No detailed information found for '#{query}'. The search did not return specific results. Try rephrasing or searching for something more specific."
    else
      result
    end
  end

  defp extract_topic_text(%{"Text" => text}) when is_binary(text) and byte_size(text) > 0 do
    # Truncate long texts
    if String.length(text) > 200 do
      String.slice(text, 0, 200) <> "..."
    else
      text
    end
  end

  defp extract_topic_text(%{"Topics" => topics}) when is_list(topics) do
    # Handle nested topic groups
    topics
    |> Enum.take(2)
    |> Enum.map(&extract_topic_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_topic_text(_), do: nil
end

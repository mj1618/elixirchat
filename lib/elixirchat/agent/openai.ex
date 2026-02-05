defmodule Elixirchat.Agent.OpenAI do
  @moduledoc """
  Module for interacting with the OpenAI Chat Completions API.
  Supports function calling (tools) for agent capabilities.
  """

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4o-mini"
  @default_max_tokens 500

  @doc """
  Sends a chat completion request to OpenAI.

  ## Options
  - `:model` - The model to use (default: gpt-4o-mini)
  - `:max_tokens` - Maximum tokens in response (default: 500)
  - `:temperature` - Sampling temperature (default: 0.7)
  - `:tools` - List of tool definitions for function calling (optional)
  - `:tool_choice` - How to select tools: "auto", "required", or specific function (optional)

  Returns:
  - `{:ok, response_text}` for regular responses
  - `{:tool_calls, tool_calls}` when the model wants to call tools
  - `{:error, reason}` on failure

  Tool calls are returned as a list of maps with keys:
  - `id` - The tool call ID (needed for the response)
  - `name` - The function name to call
  - `arguments` - The arguments as a decoded map
  """
  def chat_completion(messages, opts \\ []) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, :api_key_missing}
    else
      model = Keyword.get(opts, :model, @default_model)
      max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
      temperature = Keyword.get(opts, :temperature, 0.7)
      tools = Keyword.get(opts, :tools)
      tool_choice = Keyword.get(opts, :tool_choice)

      body =
        %{
          model: model,
          messages: messages,
          max_tokens: max_tokens,
          temperature: temperature
        }
        |> maybe_add_tools(tools, tool_choice)

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(@api_url, json: body, headers: headers, receive_timeout: 60_000) do
        {:ok, %{status: 200, body: response_body}} ->
          extract_response(response_body)

        {:ok, %{status: 401}} ->
          Logger.error("OpenAI API: Invalid API key")
          {:error, :invalid_api_key}

        {:ok, %{status: 429}} ->
          Logger.warning("OpenAI API: Rate limited")
          {:error, :rate_limited}

        {:ok, %{status: status, body: body}} ->
          Logger.error("OpenAI API error: status=#{status}, body=#{inspect(body)}")
          {:error, {:api_error, status}}

        {:error, reason} ->
          Logger.error("OpenAI API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp maybe_add_tools(body, nil, _tool_choice), do: body
  defp maybe_add_tools(body, [], _tool_choice), do: body
  defp maybe_add_tools(body, tools, tool_choice) when is_list(tools) do
    body
    |> Map.put(:tools, tools)
    |> maybe_add_tool_choice(tool_choice)
  end

  defp maybe_add_tool_choice(body, nil), do: body
  defp maybe_add_tool_choice(body, "auto"), do: Map.put(body, :tool_choice, "auto")
  defp maybe_add_tool_choice(body, "required"), do: Map.put(body, :tool_choice, "required")
  defp maybe_add_tool_choice(body, "none"), do: Map.put(body, :tool_choice, "none")
  defp maybe_add_tool_choice(body, function_name) when is_binary(function_name) do
    Map.put(body, :tool_choice, %{type: "function", function: %{name: function_name}})
  end

  # Handle tool calls response
  defp extract_response(%{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]})
       when is_list(tool_calls) and length(tool_calls) > 0 do
    parsed_calls =
      Enum.map(tool_calls, fn tool_call ->
        %{
          id: tool_call["id"],
          name: tool_call["function"]["name"],
          arguments: parse_arguments(tool_call["function"]["arguments"])
        }
      end)

    {:tool_calls, parsed_calls}
  end

  # Handle regular text response
  defp extract_response(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) do
    {:ok, String.trim(content)}
  end

  # Handle response with both content and no tool calls
  defp extract_response(%{"choices" => [%{"message" => message} | _]}) do
    case Map.get(message, "content") do
      content when is_binary(content) -> {:ok, String.trim(content)}
      nil -> {:ok, ""}
      _ -> {:error, :unexpected_response}
    end
  end

  defp extract_response(response) do
    Logger.error("Unexpected OpenAI response format: #{inspect(response)}")
    {:error, :unexpected_response}
  end

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end

  defp parse_arguments(_), do: %{}

  defp get_api_key do
    Application.get_env(:elixirchat, :openai)[:api_key] ||
      System.get_env("OPENAI_API_KEY")
  end
end

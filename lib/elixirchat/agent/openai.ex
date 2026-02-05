defmodule Elixirchat.Agent.OpenAI do
  @moduledoc """
  Module for interacting with the OpenAI Chat Completions API.
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

  Returns `{:ok, response_text}` or `{:error, reason}`.
  """
  def chat_completion(messages, opts \\ []) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, :api_key_missing}
    else
      model = Keyword.get(opts, :model, @default_model)
      max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
      temperature = Keyword.get(opts, :temperature, 0.7)

      body = %{
        model: model,
        messages: messages,
        max_tokens: max_tokens,
        temperature: temperature
      }

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

  defp extract_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, String.trim(content)}
  end

  defp extract_response(response) do
    Logger.error("Unexpected OpenAI response format: #{inspect(response)}")
    {:error, :unexpected_response}
  end

  defp get_api_key do
    Application.get_env(:elixirchat, :openai)[:api_key] ||
      System.get_env("OPENAI_API_KEY")
  end
end

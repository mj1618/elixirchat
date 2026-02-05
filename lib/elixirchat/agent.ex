defmodule Elixirchat.Agent do
  @moduledoc """
  Context for AI agent functionality in chat conversations.
  Handles detecting @agent mentions and generating AI responses.
  """

  require Logger

  alias Elixirchat.Agent.OpenAI
  alias Elixirchat.Chat
  alias Elixirchat.Accounts

  @agent_username "agent"
  @mention_pattern ~r/@agent\s+(.+)/is

  @doc """
  Gets or creates the agent system user.
  """
  def get_or_create_agent_user do
    case Accounts.get_user_by_username(@agent_username) do
      nil ->
        # Create the agent user with a random secure password
        random_password = :crypto.strong_rand_bytes(32) |> Base.encode64()
        {:ok, agent} = Accounts.create_user(%{
          username: @agent_username,
          password: random_password
        })
        agent

      agent ->
        agent
    end
  end

  @doc """
  Returns the agent username.
  """
  def agent_username, do: @agent_username

  @doc """
  Checks if a message contains an @agent mention.
  """
  def contains_mention?(content) when is_binary(content) do
    Regex.match?(@mention_pattern, content)
  end

  def contains_mention?(_), do: false

  @doc """
  Extracts the question from an @agent mention.
  Returns nil if no mention found.
  """
  def extract_question(content) when is_binary(content) do
    case Regex.run(@mention_pattern, content) do
      [_, question] -> String.trim(question)
      _ -> nil
    end
  end

  def extract_question(_), do: nil

  @doc """
  Processes a message to check for @agent mention and generate a response.
  This should be called asynchronously after a message is sent.

  Returns `:ok` if processed (or no mention), or `{:error, reason}` if failed.
  """
  def process_message(conversation_id, content) do
    if contains_mention?(content) do
      question = extract_question(content)

      if question do
        generate_and_send_response(conversation_id, question)
      else
        :ok
      end
    else
      :ok
    end
  end

  @doc """
  Generates an AI response and sends it to the conversation.
  """
  def generate_and_send_response(conversation_id, question) do
    # Get conversation context (recent messages)
    context_messages = get_conversation_context(conversation_id)

    # Build the messages for OpenAI
    messages = build_openai_messages(context_messages, question)

    case OpenAI.chat_completion(messages) do
      {:ok, response} ->
        send_agent_message(conversation_id, response)

      {:error, :api_key_missing} ->
        send_agent_message(conversation_id, "I'm sorry, but I'm not configured properly. The API key is missing.")

      {:error, :rate_limited} ->
        send_agent_message(conversation_id, "I'm receiving too many requests right now. Please try again in a moment.")

      {:error, reason} ->
        Logger.error("Agent failed to generate response: #{inspect(reason)}")
        send_agent_message(conversation_id, "I encountered an error while processing your request. Please try again later.")
    end
  end

  @doc """
  Gets recent messages from a conversation for context.
  Returns the last 10 messages.
  """
  def get_conversation_context(conversation_id) do
    Chat.list_messages(conversation_id, limit: 10)
  end

  @doc """
  Builds the OpenAI message format from conversation context.
  """
  def build_openai_messages(context_messages, question) do
    system_message = %{
      role: "system",
      content: """
      You are a helpful AI assistant in a chat application called Elixirchat.
      You are friendly, concise, and helpful. Keep your responses brief but informative.
      You have context from recent messages in the conversation to help provide relevant answers.
      When users ask about code or technical topics, provide clear explanations.
      """
    }

    # Convert chat messages to OpenAI format for context
    context =
      context_messages
      |> Enum.take(-8)  # Use last 8 messages for context
      |> Enum.map(fn msg ->
        role = if msg.sender.username == @agent_username, do: "assistant", else: "user"
        %{
          role: role,
          content: "#{msg.sender.username}: #{msg.content}"
        }
      end)

    # Add the current question
    user_message = %{
      role: "user",
      content: question
    }

    [system_message | context] ++ [user_message]
  end

  @doc """
  Sends a message as the agent user.
  """
  def send_agent_message(conversation_id, content) do
    agent = get_or_create_agent_user()

    case Chat.send_message(conversation_id, agent.id, content) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to send agent message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Checks if a user is the agent.
  """
  def is_agent?(user_id) do
    agent = get_or_create_agent_user()
    agent.id == user_id
  end

  @doc """
  Checks if a user is the agent by username.
  """
  def is_agent_username?(username) do
    username == @agent_username
  end
end

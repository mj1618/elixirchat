defmodule Elixirchat.Agent do
  @moduledoc """
  Context for AI agent functionality in chat conversations.
  Handles detecting @agent mentions and generating AI responses.
  Supports tool usage including web search.
  """

  require Logger

  alias Elixirchat.Agent.OpenAI
  alias Elixirchat.Agent.WebSearch
  alias Elixirchat.Chat
  alias Elixirchat.Accounts

  @agent_username "agent"
  @mention_pattern ~r/@agent\s+(.+)/is
  @max_tool_iterations 3

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
  Supports tool usage (web search) with an iterative loop.
  """
  def generate_and_send_response(conversation_id, question) do
    # Get conversation context (recent messages)
    context_messages = get_conversation_context(conversation_id)

    # Build the messages for OpenAI
    messages = build_openai_messages(context_messages, question)

    # Process with tools support
    process_with_tools(conversation_id, messages, 0)
  end

  defp process_with_tools(conversation_id, messages, iteration) when iteration >= @max_tool_iterations do
    Logger.warning("Agent reached max tool iterations (#{@max_tool_iterations})")
    # Make one final call without tools to get a response
    case OpenAI.chat_completion(messages) do
      {:ok, response} ->
        send_agent_message(conversation_id, response)

      {:error, reason} ->
        Logger.error("Agent failed to generate final response: #{inspect(reason)}")
        send_agent_message(conversation_id, "I encountered an error while processing your request. Please try again later.")
    end
  end

  defp process_with_tools(conversation_id, messages, iteration) do
    tools = get_tools()

    # On first iteration, check if this looks like a factual question that needs search
    # Use "required" to force tool usage, otherwise "auto"
    tool_choice = if iteration == 0 and should_force_search?(messages), do: "required", else: "auto"

    case OpenAI.chat_completion(messages, tools: tools, tool_choice: tool_choice) do
      {:ok, response} ->
        send_agent_message(conversation_id, response)

      {:tool_calls, tool_calls} ->
        # Execute tools and continue the conversation
        Logger.info("Agent calling tools: #{inspect(Enum.map(tool_calls, & &1.name))}")
        {updated_messages, _results} = execute_tool_calls(messages, tool_calls)
        process_with_tools(conversation_id, updated_messages, iteration + 1)

      {:error, :api_key_missing} ->
        send_agent_message(conversation_id, "I'm sorry, but I'm not configured properly. The API key is missing.")

      {:error, :rate_limited} ->
        send_agent_message(conversation_id, "I'm receiving too many requests right now. Please try again in a moment.")

      {:error, reason} ->
        Logger.error("Agent failed to generate response: #{inspect(reason)}")
        send_agent_message(conversation_id, "I encountered an error while processing your request. Please try again later.")
    end
  end

  # Check if the question looks like it needs factual information from the web
  defp should_force_search?(messages) do
    # Get the last user message (the question)
    case Enum.find(Enum.reverse(messages), fn m -> m.role == "user" end) do
      nil -> false
      %{content: content} ->
        content = String.downcase(content)

        # Skip search for simple greetings/casual chat
        casual_patterns = ~w(hello hi hey thanks thank you bye goodbye ok okay sure yes no)
        is_casual = Enum.any?(casual_patterns, fn pattern ->
          String.trim(content) == pattern or String.starts_with?(content, pattern <> " ") and String.length(content) < 20
        end)

        if is_casual do
          false
        else
          # Force search for questions or factual requests
          question_patterns = ["what", "who", "when", "where", "why", "how", "tell me", "explain",
                               "look up", "search", "find", "latest", "current", "recent", "news",
                               "version", "?"]
          Enum.any?(question_patterns, fn pattern -> String.contains?(content, pattern) end)
        end
    end
  end

  defp execute_tool_calls(messages, tool_calls) do
    # Add the assistant message with tool calls
    assistant_message = %{
      role: "assistant",
      tool_calls: Enum.map(tool_calls, fn call ->
        %{
          id: call.id,
          type: "function",
          function: %{
            name: call.name,
            arguments: Jason.encode!(call.arguments)
          }
        }
      end)
    }

    messages = messages ++ [assistant_message]

    # Execute each tool call and collect results
    {tool_messages, results} =
      Enum.map_reduce(tool_calls, [], fn call, acc ->
        result = execute_tool(call.name, call.arguments)
        tool_message = %{
          role: "tool",
          tool_call_id: call.id,
          content: result
        }
        {tool_message, [{call.name, result} | acc]}
      end)

    {messages ++ tool_messages, Enum.reverse(results)}
  end

  defp execute_tool("web_search", %{"query" => query}) do
    Logger.info("Agent executing web_search with query: #{query}")

    case WebSearch.search(query) do
      {:ok, results} ->
        results

      {:error, reason} ->
        Logger.error("Web search failed: #{inspect(reason)}")
        "Web search failed. Unable to retrieve information at this time."
    end
  end

  defp execute_tool(name, _args) do
    Logger.warning("Agent tried to call unknown tool: #{name}")
    "Unknown tool: #{name}"
  end

  @doc """
  Returns the tool definitions for OpenAI function calling.
  """
  def get_tools do
    [
      %{
        type: "function",
        function: %{
          name: "web_search",
          description: "Search the web for current information. Use this when you need to look up facts, current events, or information you're unsure about.",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "The search query to look up"
              }
            },
            required: ["query"]
          }
        }
      }
    ]
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

      IMPORTANT: You have access to a web_search tool. You MUST use it to look up information for most questions.
      ALWAYS use web_search when:
      - The user asks about ANY factual information (people, places, events, technology, etc.)
      - The user asks "what is", "who is", "when did", "how does", etc.
      - The user asks about current events, news, or recent developments
      - The user asks about software versions, documentation, or technical details
      - You would otherwise need to rely on your training data

      Only skip web_search for:
      - Simple greetings or casual conversation
      - Questions about this chat application itself
      - Requests that don't require factual information

      When you get search results, synthesize them into a helpful, concise response.
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

    # Broadcast that agent is done processing
    Chat.broadcast_agent_processing(conversation_id, false)

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

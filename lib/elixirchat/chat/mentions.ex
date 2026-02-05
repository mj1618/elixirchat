defmodule Elixirchat.Chat.Mentions do
  @moduledoc """
  Module for handling @mentions in chat messages.
  Provides functions to extract, validate, and render @mentions.
  """

  alias Elixirchat.Repo
  alias Elixirchat.Chat.ConversationMember
  import Ecto.Query

  @mention_regex ~r/@([a-zA-Z0-9_]+)/

  @doc """
  Extracts all @mentions from message content.
  Returns list of usernames (without the @ symbol).
  """
  def extract_usernames(content) when is_binary(content) do
    @mention_regex
    |> Regex.scan(content)
    |> Enum.map(fn [_, username] -> username end)
    |> Enum.uniq()
  end

  def extract_usernames(_), do: []

  @doc """
  Gets users that can be mentioned in a conversation.
  Filters by search term and returns up to 5 results.
  """
  def get_mentionable_users(conversation_id, search_term) when is_binary(search_term) do
    search = "%#{String.downcase(search_term)}%"

    from(m in ConversationMember,
      join: u in assoc(m, :user),
      where: m.conversation_id == ^conversation_id,
      where: ilike(u.username, ^search),
      select: u,
      limit: 5,
      order_by: u.username
    )
    |> Repo.all()
  end

  def get_mentionable_users(_, _), do: []

  @doc """
  Resolves mentions to user IDs.
  Only returns IDs for users who exist and are in the conversation.
  """
  def resolve_mentions(content, conversation_id) when is_binary(content) do
    usernames = extract_usernames(content)

    if usernames == [] do
      []
    else
      # Get all members of the conversation
      members =
        from(m in ConversationMember,
          join: u in assoc(m, :user),
          where: m.conversation_id == ^conversation_id,
          select: u
        )
        |> Repo.all()

      member_map = Map.new(members, fn u -> {String.downcase(u.username), u.id} end)

      usernames
      |> Enum.map(&String.downcase/1)
      |> Enum.filter(&Map.has_key?(member_map, &1))
      |> Enum.map(&Map.get(member_map, &1))
    end
  end

  def resolve_mentions(_, _), do: []

  @doc """
  Checks if the given content contains any @mentions.
  """
  def has_mentions?(content) when is_binary(content) do
    Regex.match?(@mention_regex, content)
  end

  def has_mentions?(_), do: false

  @doc """
  Renders message content with highlighted mentions.
  Returns HTML with mentions wrapped in styled spans.

  Note: The output should be rendered with Phoenix.HTML.raw/1 to display properly.
  """
  def render_with_mentions(content, conversation_id \\ nil)

  def render_with_mentions(content, conversation_id) when is_binary(content) do
    # Get valid member usernames if conversation_id provided
    valid_usernames =
      if conversation_id do
        from(m in ConversationMember,
          join: u in assoc(m, :user),
          where: m.conversation_id == ^conversation_id,
          select: u.username
        )
        |> Repo.all()
        |> Enum.map(&String.downcase/1)
        |> MapSet.new()
      else
        nil
      end

    Regex.replace(@mention_regex, content, fn full, username ->
      # Check if this is a valid user mention (if we have conversation context)
      is_valid =
        if valid_usernames do
          MapSet.member?(valid_usernames, String.downcase(username))
        else
          true
        end

      if is_valid do
        escaped_username = Phoenix.HTML.html_escape(username) |> Phoenix.HTML.safe_to_string()
        escaped_full = Phoenix.HTML.html_escape(full) |> Phoenix.HTML.safe_to_string()
        ~s(<span class="mention text-primary font-semibold" data-username="#{escaped_username}">#{escaped_full}</span>)
      else
        full
      end
    end)
  end

  def render_with_mentions(content, _), do: content || ""
end

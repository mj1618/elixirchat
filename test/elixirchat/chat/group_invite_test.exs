defmodule Elixirchat.Chat.GroupInviteTest do
  use Elixirchat.DataCase

  alias Elixirchat.Chat
  alias Elixirchat.Chat.GroupInvite

  describe "group invites" do
    setup do
      user1 = insert_user(username: "user1", password: "password123")
      user2 = insert_user(username: "user2", password: "password123")
      {:ok, conversation} = Chat.create_group_conversation("Test Group", [user1.id])

      %{user1: user1, user2: user2, conversation: conversation}
    end

    test "create_group_invite/3 creates an invite with default options", %{
      user1: user1,
      conversation: conversation
    } do
      assert {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id)
      assert invite.token != nil
      assert invite.conversation_id == conversation.id
      assert invite.created_by_id == user1.id
      assert invite.use_count == 0
    end

    test "create_group_invite/3 creates an invite with custom expiration", %{
      user1: user1,
      conversation: conversation
    } do
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert {:ok, invite} =
               Chat.create_group_invite(conversation.id, user1.id, expires_at: expires_at)

      assert invite.expires_at != nil
    end

    test "create_group_invite/3 creates an invite with max_uses", %{
      user1: user1,
      conversation: conversation
    } do
      assert {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id, max_uses: 10)
      assert invite.max_uses == 10
    end

    test "get_invite_by_token/1 returns invite with token", %{
      user1: user1,
      conversation: conversation
    } do
      {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id)
      found_invite = Chat.get_invite_by_token(invite.token)

      assert found_invite.id == invite.id
      assert found_invite.conversation != nil
    end

    test "get_invite_by_token/1 returns nil for invalid token" do
      assert Chat.get_invite_by_token("invalid_token") == nil
    end

    test "is_invite_valid?/1 returns true for valid invite", %{
      user1: user1,
      conversation: conversation
    } do
      {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id)
      assert Chat.is_invite_valid?(invite) == true
    end

    test "is_invite_valid?/1 returns false for expired invite", %{
      user1: user1,
      conversation: conversation
    } do
      # Create an invite with an expiration in the past
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id, expires_at: past_time)

      assert Chat.is_invite_valid?(invite) == false
    end

    test "is_invite_valid?/1 returns false when max_uses reached", %{
      user1: user1,
      conversation: conversation
    } do
      {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id, max_uses: 1)

      # Manually set use_count to max_uses
      {:ok, updated_invite} =
        invite
        |> GroupInvite.changeset(%{use_count: 1})
        |> Elixirchat.Repo.update()

      assert Chat.is_invite_valid?(updated_invite) == false
    end

    test "use_invite/2 adds user to group and increments use_count", %{
      user1: user1,
      user2: user2,
      conversation: conversation
    } do
      {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id)

      assert {:ok, _conversation} = Chat.use_invite(invite.token, user2.id)

      # Verify user2 is now a member
      assert Chat.member?(conversation.id, user2.id)

      # Verify use_count was incremented
      updated_invite = Chat.get_invite_by_token(invite.token)
      assert updated_invite.use_count == 1
    end

    test "use_invite/2 returns error for already member", %{
      user1: user1,
      conversation: conversation
    } do
      {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id)

      # user1 is already a member
      assert {:error, :already_member} = Chat.use_invite(invite.token, user1.id)
    end

    test "use_invite/2 returns error for invalid invite" do
      assert {:error, :invalid_invite} = Chat.use_invite("invalid_token", 1)
    end

    test "revoke_invite/2 allows conversation member to revoke invite", %{
      user1: user1,
      conversation: conversation
    } do
      {:ok, invite} = Chat.create_group_invite(conversation.id, user1.id)

      assert :ok = Chat.revoke_invite(conversation.id, user1.id)

      # Verify invite no longer exists
      assert Chat.get_invite_by_token(invite.token) == nil
    end

    test "generate_token/0 generates unique tokens" do
      token1 = GroupInvite.generate_token()
      token2 = GroupInvite.generate_token()

      assert token1 != token2
      assert String.length(token1) > 10
    end
  end

  # Helper function to create a user
  defp insert_user(attrs) do
    password = Keyword.get(attrs, :password, "password123")
    {:ok, user} =
      Elixirchat.Accounts.create_user(%{
        username: Keyword.fetch!(attrs, :username),
        password: password,
        password_confirmation: password
      })

    user
  end
end

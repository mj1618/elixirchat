defmodule ElixirchatWeb.JoinGroupLive do
  @moduledoc """
  LiveView for handling group invite links.
  Shows group info and allows users to join via invite link.
  """

  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invite = Chat.get_invite_by_token(token)

    cond do
      is_nil(invite) ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid invite link")
         |> assign(invite: nil, valid: false, member_count: 0, already_member: false)}

      !Chat.is_invite_valid?(invite) ->
        {:ok,
         socket
         |> put_flash(:error, "This invite link has expired or reached its limit")
         |> assign(invite: invite, valid: false, member_count: 0, already_member: false)}

      true ->
        member_count = Chat.get_member_count(invite.conversation_id)
        already_member =
          socket.assigns[:current_user] &&
          Chat.member?(invite.conversation_id, socket.assigns.current_user.id)

        {:ok,
         socket
         |> assign(
           invite: invite,
           valid: true,
           member_count: member_count,
           already_member: already_member
         )}
    end
  end

  @impl true
  def handle_event("join_group", _, socket) do
    case Chat.use_invite(socket.assigns.invite.token, socket.assigns.current_user.id) do
      {:ok, conversation} ->
        {:noreply,
         socket
         |> put_flash(:info, "You joined #{conversation.name}!")
         |> push_navigate(to: ~p"/chats/#{conversation.id}")}

      {:error, :already_member} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/chats/#{socket.assigns.invite.conversation_id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not join group")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-base-200 p-4">
      <div class="card bg-base-100 shadow-xl max-w-md w-full">
        <div class="card-body text-center">
          <%= if @valid do %>
            <div class="avatar avatar-placeholder mx-auto mb-4">
              <div class="bg-secondary text-secondary-content rounded-full w-20 h-20 flex items-center justify-center">
                <span class="text-3xl font-bold">{String.first(@invite.conversation.name) |> String.upcase()}</span>
              </div>
            </div>
            <h2 class="card-title justify-center text-2xl mb-2">
              Join {@invite.conversation.name}
            </h2>
            <p class="text-base-content/60 mb-4">
              {@member_count} {if @member_count == 1, do: "member", else: "members"}
            </p>

            <%= if @current_user do %>
              <%= if @already_member do %>
                <p class="mb-4">You're already a member of this group.</p>
                <.link navigate={~p"/chats/#{@invite.conversation_id}"} class="btn btn-primary">
                  Go to Chat
                </.link>
              <% else %>
                <button phx-click="join_group" class="btn btn-primary btn-lg">
                  Join Group
                </button>
              <% end %>
            <% else %>
              <p class="mb-4">Please log in to join this group.</p>
              <.link navigate={~p"/login?redirect=/join/#{@invite.token}"} class="btn btn-primary">
                Log in to Join
              </.link>
            <% end %>
          <% else %>
            <div class="text-error mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-16 h-16 mx-auto mb-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
              </svg>
              <h2 class="card-title justify-center">Invalid Invite</h2>
              <p>This invite link is invalid, expired, or has reached its maximum uses.</p>
            </div>
            <.link navigate={~p"/chats"} class="btn btn-ghost">
              Go to Chat
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

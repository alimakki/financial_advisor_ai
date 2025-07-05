defmodule FinancialAdvisorAiWeb.ConversationLive.Index do
  use FinancialAdvisorAiWeb, :live_view

  alias FinancialAdvisorAi.AI

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Conversations
        <:actions>
          <.button variant="primary" navigate={~p"/conversations/new"}>
            <.icon name="hero-plus" /> New Conversation
          </.button>
        </:actions>
      </.header>

      <.table
        id="conversations"
        rows={@streams.conversations}
        row_click={fn {_id, conversation} -> JS.navigate(~p"/conversations/#{conversation}") end}
      >
        <:col :let={{_id, conversation}} label="Title">{conversation.title}</:col>
        <:action :let={{_id, conversation}}>
          <div class="sr-only">
            <.link navigate={~p"/conversations/#{conversation}"}>Show</.link>
          </div>
          <.link navigate={~p"/conversations/#{conversation}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, conversation}}>
          <.link
            phx-click={JS.push("delete", value: %{id: conversation.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      AI.subscribe_conversations(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Conversations")
     |> stream(:conversations, AI.list_conversations(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    conversation = AI.get_conversation!(socket.assigns.current_scope, id)
    {:ok, _} = AI.delete_conversation(socket.assigns.current_scope, conversation)

    {:noreply, stream_delete(socket, :conversations, conversation)}
  end

  @impl true
  def handle_info({type, %FinancialAdvisorAi.AI.Conversation{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :conversations, AI.list_conversations(socket.assigns.current_scope),
       reset: true
     )}
  end
end

defmodule FinancialAdvisorAiWeb.ConversationLive.Show do
  use FinancialAdvisorAiWeb, :live_view

  alias FinancialAdvisorAi.AI

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Conversation {@conversation.id}
        <:subtitle>This is a conversation record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/conversations"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/conversations/#{@conversation}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit conversation
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Title">{@conversation.title}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      AI.subscribe_conversations(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Conversation")
     |> assign(:conversation, AI.get_conversation!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %FinancialAdvisorAi.AI.Conversation{id: id} = conversation},
        %{assigns: %{conversation: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :conversation, conversation)}
  end

  def handle_info(
        {:deleted, %FinancialAdvisorAi.AI.Conversation{id: id}},
        %{assigns: %{conversation: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current conversation was deleted.")
     |> push_navigate(to: ~p"/conversations")}
  end

  def handle_info({type, %FinancialAdvisorAi.AI.Conversation{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end

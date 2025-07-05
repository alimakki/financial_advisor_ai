defmodule FinancialAdvisorAiWeb.ChatLive do
  use FinancialAdvisorAiWeb, :live_view

  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.AI.{Conversation, Message}
  alias FinancialAdvisorAi.AI.{RagService, LlmService}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        FinancialAdvisorAi.PubSub,
        "chat:#{socket.assigns.current_scope.user.id}"
      )
    end

    # Get or create active conversation
    user_id = socket.assigns.current_scope.user.id
    conversations = AI.list_conversations(user_id)

    active_conversation =
      case conversations do
        [conversation | _] ->
          conversation

        [] ->
          {:ok, conversation} =
            AI.create_conversation(%{
              title: "New Conversation",
              user_id: user_id
            })

          conversation
      end

    messages = AI.list_messages(active_conversation.id)

    {:ok,
     socket
     |> assign(:conversations, conversations)
     |> assign(:active_conversation, active_conversation)
     |> assign(:messages, messages)
     |> assign(:message_form, to_form(%{"content" => ""}))
     |> stream(:messages, messages)}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) when content != "" do
    user_id = socket.assigns.current_scope.user.id
    conversation_id = socket.assigns.active_conversation.id

    # Create user message
    {:ok, user_message} =
      AI.create_message(%{
        conversation_id: conversation_id,
        role: "user",
        content: content
      })

    # Broadcast to all connected sessions
    Phoenix.PubSub.broadcast(
      FinancialAdvisorAi.PubSub,
      "chat:#{user_id}",
      {:new_message, user_message}
    )

    # Use RAG to search for relevant context
    context = RagService.search_by_question_type(user_id, content)

    # Check if this is an action request and use tool calling if appropriate
    ai_response =
      cond do
        contains_action_keywords?(content) ->
          case LlmService.generate_response_with_tools(content, context, user_id) do
            {:ok, response} -> response
            {:error, _reason} -> generate_fallback_response(content, context)
          end

        true ->
          case LlmService.generate_response(content, context) do
            {:ok, response} -> response
            {:error, _reason} -> generate_fallback_response(content, context)
          end
      end

    {:ok, ai_message} =
      AI.create_message(%{
        conversation_id: conversation_id,
        role: "assistant",
        content: ai_response
      })

    Phoenix.PubSub.broadcast(
      FinancialAdvisorAi.PubSub,
      "chat:#{user_id}",
      {:new_message, ai_message}
    )

    {:noreply,
     socket
     |> assign(:message_form, to_form(%{"content" => ""}))}
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  # Check if the user message contains action keywords that would benefit from tool calling
  defp contains_action_keywords?(content) do
    action_keywords = [
      "schedule",
      "send email",
      "create contact",
      "add contact",
      "send a message",
      "book appointment",
      "set up meeting",
      "create task",
      "remind me",
      "follow up"
    ]

    content_lower = String.downcase(content)
    Enum.any?(action_keywords, &String.contains?(content_lower, &1))
  end

  # Fallback response when LLM service is unavailable
  defp generate_fallback_response(question, context) do
    cond do
      # Handle specific question types
      String.contains?(String.downcase(question), ["kid", "child", "baseball", "soccer"]) ->
        handle_family_question(context)

      String.contains?(String.downcase(question), ["stock", "aapl", "investment"]) ->
        handle_stock_question(context)

      String.contains?(String.downcase(question), ["meeting", "appointment", "schedule"]) ->
        handle_meeting_question(context)

      # General questions
      true ->
        handle_general_question(question, context)
    end
  end

  defp handle_family_question(context) do
    case context.emails do
      [] ->
        "I didn't find any emails mentioning family activities like baseball or kids' sports. Would you like me to search for different keywords?"

      emails ->
        family_mentions =
          emails
          |> Enum.map(fn email ->
            "• #{email.sender}: #{email.content_preview}"
          end)
          |> Enum.join("\n")

        "I found #{length(emails)} emails mentioning family activities:\n\n#{family_mentions}\n\nWould you like me to provide more details about any of these conversations?"
    end
  end

  defp handle_stock_question(context) do
    case context.emails do
      [] ->
        "I didn't find any emails discussing stocks or investments. Would you like me to search with different terms?"

      emails ->
        stock_mentions =
          emails
          |> Enum.map(fn email ->
            "• #{email.sender}: #{email.content_preview}"
          end)
          |> Enum.join("\n")

        "I found #{length(emails)} emails about stocks or investments:\n\n#{stock_mentions}\n\nWould you like me to analyze any specific investment discussions?"
    end
  end

  defp handle_meeting_question(context) do
    case context.emails do
      [] ->
        "I didn't find any emails about meetings or appointments. Would you like me to check your calendar or search with different terms?"

      emails ->
        meeting_mentions =
          emails
          |> Enum.map(fn email ->
            "• #{email.sender}: #{email.content_preview}"
          end)
          |> Enum.join("\n")

        "I found #{length(emails)} emails about meetings or scheduling:\n\n#{meeting_mentions}\n\nWould you like me to help schedule something or get more details?"
    end
  end

  defp handle_general_question(question, context) do
    case {context.emails, context.contacts} do
      {[], []} ->
        "I understand you're asking: \"#{question}\"\n\nI'm ready to help with your financial advisory tasks! I can:\n• Search through your emails and contacts\n• Help schedule appointments\n• Manage client communications\n• Analyze client information\n\nOnce you connect your Gmail, Calendar, and HubSpot accounts, I'll have access to much more context to provide detailed answers."

      {emails, contacts} ->
        email_summary = if length(emails) > 0, do: "#{length(emails)} relevant emails", else: ""

        contact_summary =
          if length(contacts) > 0, do: "#{length(contacts)} related contacts", else: ""

        summary_parts =
          [email_summary, contact_summary] |> Enum.reject(&(&1 == "")) |> Enum.join(" and ")

        "Based on your question \"#{question}\", I found #{summary_parts}.\n\n#{context.summary}\n\nWould you like me to provide more specific information about any of these results?"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50 flex">
        <!-- Sidebar -->
        <div class="w-80 bg-white border-r border-gray-200 flex flex-col">
          <!-- Header -->
          <div class="p-4 border-b border-gray-200">
            <button class="w-full flex items-center justify-center space-x-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg px-4 py-2 text-sm font-medium transition-colors">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                />
              </svg>
              <span>New Conversation</span>
            </button>
          </div>
          
    <!-- Conversations List -->
          <div class="flex-1 overflow-y-auto p-2 space-y-1">
            <%= for conversation <- @conversations do %>
              <div class={"p-3 hover:bg-gray-50 rounded-lg cursor-pointer #{if conversation.id == @active_conversation.id, do: "border-l-2 border-blue-500 bg-blue-50", else: ""}"}>
                <h3 class="font-medium text-gray-900 text-sm">{conversation.title}</h3>
                <p class="text-xs text-gray-500 mt-1">
                  {Calendar.strftime(conversation.updated_at, "%b %d")}
                </p>
              </div>
            <% end %>
          </div>
          
    <!-- Integration Status -->
          <div class="p-4 border-t border-gray-200">
            <h4 class="text-sm font-medium text-gray-700 mb-3">Connected Services</h4>
            <div class="space-y-2">
              <div class="flex items-center justify-between text-sm">
                <span class="text-gray-600">Gmail</span>
                <span class="text-green-600 text-xs">Connected</span>
              </div>
              <div class="flex items-center justify-between text-sm">
                <span class="text-gray-600">Calendar</span>
                <span class="text-green-600 text-xs">Connected</span>
              </div>
              <div class="flex items-center justify-between text-sm">
                <span class="text-gray-600">HubSpot</span>
                <span class="text-gray-600 text-xs">Not Connected</span>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Chat Area -->
        <div class="flex-1 flex flex-col">
          <!-- Chat Header -->
          <div class="px-6 py-4 border-b border-gray-200 bg-white">
            <h2 class="text-lg font-semibold text-gray-900">{@active_conversation.title}</h2>
            <p class="text-sm text-gray-500">
              AI agent ready to help with your financial advisory tasks
            </p>
          </div>
          
    <!-- Messages -->
          <div class="flex-1 overflow-y-auto p-6 space-y-6" id="messages" phx-update="stream">
            <%= for {id, message} <- @streams.messages do %>
              <div id={id} class={"flex space-x-3 #{if message.role == "user", do: "justify-end"}"}>
                <%= if message.role == "assistant" do %>
                  <div class="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center flex-shrink-0">
                    <svg class="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                <% end %>

                <div class="flex-1 max-w-3xl">
                  <div class={[
                    "rounded-lg p-4",
                    if(message.role == "user",
                      do: "bg-blue-600 text-white ml-auto",
                      else: "bg-gray-50 text-gray-800"
                    )
                  ]}>
                    <p class="whitespace-pre-wrap">{message.content}</p>
                  </div>
                  <p class="text-xs text-gray-500 mt-2">
                    {Calendar.strftime(message.inserted_at, "%I:%M %p")}
                  </p>
                </div>

                <%= if message.role == "user" do %>
                  <div class="w-8 h-8 bg-gray-300 rounded-full flex-shrink-0"></div>
                <% end %>
              </div>
            <% end %>
          </div>
          
    <!-- Input Area -->
          <div class="border-t border-gray-200 p-4 bg-white">
            <.form
              for={@message_form}
              phx-submit="send_message"
              id="message-form"
              class="flex space-x-3"
            >
              <div class="flex-1">
                <.input
                  field={@message_form[:content]}
                  type="text"
                  placeholder="Ask me about clients, schedule meetings, or give me tasks..."
                  class="w-full border border-gray-300 rounded-lg px-4 py-3 pr-12 focus:ring-2 focus:ring-blue-500 focus:border-transparent text-gray-900 placeholder-gray-500 bg-white"
                  autocomplete="off"
                />
              </div>
              <button
                type="submit"
                class="px-4 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"
                  />
                </svg>
              </button>
            </.form>
            <p class="text-xs text-gray-500 mt-2">
              Connected to Gmail, Calendar, and HubSpot • AI Agent with Tool Calling Ready
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

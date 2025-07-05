defmodule FinancialAdvisorAiWeb.ChatLive do
  use FinancialAdvisorAiWeb, :live_view

  alias FinancialAdvisorAi.AI
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

    # Check integration status
    google_integration = AI.get_integration(user_id, "google")
    hubspot_integration = AI.get_integration(user_id, "hubspot")

    {:ok,
     socket
     |> assign(:conversations, conversations)
     |> assign(:active_conversation, active_conversation)
     |> assign(:messages, messages)
     |> assign(:message_form, to_form(%{"content" => ""}))
     |> assign(:google_connected, !is_nil(google_integration))
     |> assign(:hubspot_connected, !is_nil(hubspot_integration))
     |> assign(:is_typing, false)
     |> stream(:messages, messages)}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) when content != "" do
    user_id = socket.assigns.current_scope.user.id
    conversation_id = socket.assigns.active_conversation.id

    # Show typing indicator
    socket = assign(socket, :is_typing, true)

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
            _ -> generate_fallback_response(content, context)
          end

        true ->
          case LlmService.generate_response(content, context) do
            {:ok, response} -> response
            _ -> generate_fallback_response(content, context)
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
     |> assign(:message_form, to_form(%{"content" => ""}))
     |> assign(:is_typing, false)}
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

  # Enhanced fallback response when LLM service is unavailable
  defp generate_fallback_response(question, context) do
    cond do
      # Handle specific question types with detailed RAG results
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
        "🔍 I searched through your emails but didn't find any mentions of family activities like baseball or kids' sports.\n\n💡 **Suggestions:**\n• Try searching with different keywords like 'child', 'son', 'daughter', or specific sports\n• Connect your Gmail account for access to your full email history"

      emails ->
        email_details =
          emails
          |> Enum.with_index(1)
          |> Enum.map(fn {email, index} ->
            preview = String.slice(email.content_preview, 0, 150)

            "**#{index}. #{extract_name(email.sender)}** (#{email.sender})\n   📧 #{email.subject}\n   💬 \"#{preview}...\"\n   📅 #{format_date(email.date)}"
          end)
          |> Enum.join("\n\n")

        "🏟️ **Found #{length(emails)} emails about family activities:**\n\n#{email_details}\n\n💡 **What would you like me to help with?**\n• Draft a response to any of these emails\n• Schedule time around these activities\n• Create a follow-up task\n• Search for more specific details"
    end
  end

  defp handle_stock_question(context) do
    case context.emails do
      [] ->
        "📈 I searched through your emails but didn't find any discussions about stocks or investments.\n\n💡 **Suggestions:**\n• Try searching for specific stock symbols (AAPL, TSLA, etc.)\n• Search for keywords like 'portfolio', 'market', or 'trading'\n• Connect your Gmail account for access to your full email history"

      emails ->
        email_details =
          emails
          |> Enum.with_index(1)
          |> Enum.map(fn {email, index} ->
            preview = String.slice(email.content_preview, 0, 150)

            "**#{index}. #{extract_name(email.sender)}** (#{email.sender})\n   📧 #{email.subject}\n   💬 \"#{preview}...\"\n   📅 #{format_date(email.date)}"
          end)
          |> Enum.join("\n\n")

        "💰 **Found #{length(emails)} emails about investments:**\n\n#{email_details}\n\n💡 **What would you like me to help with?**\n• Analyze these investment discussions\n• Draft responses to client questions\n• Schedule follow-up meetings\n• Create investment tracking tasks"
    end
  end

  defp handle_meeting_question(context) do
    case context.emails do
      [] ->
        "📅 I searched through your emails but didn't find any discussions about meetings or appointments.\n\n💡 **Suggestions:**\n• Connect your Google Calendar for scheduling assistance\n• Try searching for 'call', 'appointment', or 'available'\n• Connect your Gmail account for access to scheduling emails"

      emails ->
        email_details =
          emails
          |> Enum.with_index(1)
          |> Enum.map(fn {email, index} ->
            preview = String.slice(email.content_preview, 0, 150)

            "**#{index}. #{extract_name(email.sender)}** (#{email.sender})\n   📧 #{email.subject}\n   💬 \"#{preview}...\"\n   📅 #{format_date(email.date)}"
          end)
          |> Enum.join("\n\n")

        "🗓️ **Found #{length(emails)} emails about scheduling:**\n\n#{email_details}\n\n💡 **What would you like me to help with?**\n• Schedule these requested meetings\n• Check your calendar availability\n• Send confirmation emails\n• Create scheduling tasks"
    end
  end

  defp handle_general_question(question, context) do
    case {context.emails, context.contacts} do
      {[], []} ->
        "🤖 I'm your AI Financial Advisor assistant, ready to help!\n\n📧 **I can help you with:**\n• Searching through your emails and contacts\n• Scheduling appointments with clients\n• Managing client communications\n• Analyzing client information\n• Creating and tracking tasks\n\n🔗 **To unlock my full potential:**\nConnect your Gmail, Calendar, and HubSpot accounts using the sidebar. Once connected, I'll have access to your data to provide detailed, contextual responses.\n\n💬 **Try asking me:**\n• \"Who mentioned [topic] in recent emails?\"\n• \"Schedule a meeting with [client]\"\n• \"What's my calendar looking like?\""

      {emails, contacts} ->
        email_summary = if length(emails) > 0, do: "#{length(emails)} relevant emails", else: ""

        contact_summary =
          if length(contacts) > 0, do: "#{length(contacts)} related contacts", else: ""

        summary_parts =
          [email_summary, contact_summary] |> Enum.reject(&(&1 == "")) |> Enum.join(" and ")

        email_preview =
          if length(emails) > 0 do
            top_emails =
              emails
              |> Enum.take(3)
              |> Enum.map(fn email ->
                "• #{extract_name(email.sender)}: #{email.subject}"
              end)
              |> Enum.join("\n")

            "\n\n📧 **Top Results:**\n#{top_emails}"
          else
            ""
          end

        "🔍 **Search Results for:** \"#{question}\"\n\nI found #{summary_parts} that might be relevant.#{email_preview}\n\n💡 **To get more detailed analysis:**\n• Connect your accounts for full AI processing\n• Ask more specific questions\n• Try different search terms\n\n🤖 **I'm here to help with:** client management, scheduling, email analysis, and task automation!"
    end
  end

  # Helper functions for better formatting
  defp extract_name(email) do
    case String.split(email, "@") do
      [name | _] ->
        name
        |> String.split(".")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      _ ->
        email
    end
  end

  defp format_date(date) when is_struct(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  defp format_date(_), do: "Recent"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 flex">
        <!-- Enhanced Sidebar -->
        <div class="w-80 bg-white border-r border-gray-200 flex flex-col shadow-lg">
          <!-- Header -->
          <div class="p-4 border-b border-gray-200 bg-gradient-to-r from-blue-600 to-blue-700">
            <button class="w-full flex items-center justify-center space-x-2 bg-white bg-opacity-20 hover:bg-opacity-30 text-white rounded-lg px-4 py-3 text-sm font-medium transition-all duration-200 backdrop-blur-sm">
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
          <div class="flex-1 overflow-y-auto p-3 space-y-2">
            <%= for conversation <- @conversations do %>
              <div class={"p-3 hover:bg-gray-50 rounded-xl cursor-pointer transition-all duration-200 #{if conversation.id == @active_conversation.id, do: "border-l-4 border-blue-500 bg-blue-50", else: "border-l-4 border-transparent"}"}>
                <h3 class="font-medium text-gray-900 text-sm">{conversation.title}</h3>
                <p class="text-xs text-gray-500 mt-1">
                  {Calendar.strftime(conversation.updated_at, "%b %d")}
                </p>
              </div>
            <% end %>
          </div>
          
    <!-- Enhanced Integration Status -->
          <div class="p-4 border-t border-gray-200 bg-gray-50">
            <h4 class="text-sm font-semibold text-gray-700 mb-4 flex items-center">
              <svg class="w-4 h-4 mr-2 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                <path d="M13 6a3 3 0 11-6 0 3 3 0 016 0zM18 8a2 2 0 11-4 0 2 2 0 014 0zM14 15a4 4 0 00-8 0v3h8v-3z" />
              </svg>
              Connected Services
            </h4>
            <div class="space-y-3">
              <div class="flex items-center justify-between p-3 rounded-lg bg-white border border-gray-200">
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 rounded-full bg-red-100 flex items-center justify-center">
                    <svg class="w-4 h-4 text-red-600" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
                      <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
                    </svg>
                  </div>
                  <span class="text-sm font-medium text-gray-700">Gmail & Calendar</span>
                </div>
                <%= if @google_connected do %>
                  <span class="px-2 py-1 text-xs font-medium text-green-700 bg-green-100 rounded-full">
                    Connected
                  </span>
                <% else %>
                  <a
                    href="/auth/google"
                    class="px-3 py-1 text-xs font-medium text-blue-700 bg-blue-100 hover:bg-blue-200 rounded-full transition-colors"
                  >
                    Connect
                  </a>
                <% end %>
              </div>

              <div class="flex items-center justify-between p-3 rounded-lg bg-white border border-gray-200">
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 rounded-full bg-orange-100 flex items-center justify-center">
                    <svg class="w-4 h-4 text-orange-600" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" />
                    </svg>
                  </div>
                  <span class="text-sm font-medium text-gray-700">HubSpot CRM</span>
                </div>
                <%= if @hubspot_connected do %>
                  <span class="px-2 py-1 text-xs font-medium text-green-700 bg-green-100 rounded-full">
                    Connected
                  </span>
                <% else %>
                  <a
                    href="/auth/hubspot"
                    class="px-3 py-1 text-xs font-medium text-blue-700 bg-blue-100 hover:bg-blue-200 rounded-full transition-colors"
                  >
                    Connect
                  </a>
                <% end %>
              </div>
            </div>

            <%= unless @google_connected or @hubspot_connected do %>
              <div class="mt-4 p-3 bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg border border-blue-200">
                <p class="text-xs text-blue-700 font-semibold mb-2">🚀 Get Started</p>
                <p class="text-xs text-blue-600">
                  Connect your accounts to unlock the full power of your AI assistant!
                </p>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Enhanced Chat Area -->
        <div class="flex-1 flex flex-col">
          <!-- Chat Header with Status -->
          <div class="px-6 py-4 border-b border-gray-200 bg-white shadow-sm">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-semibold text-gray-900">{@active_conversation.title}</h2>
                <p class="text-sm text-gray-500">
                  AI agent ready to help with your financial advisory tasks
                </p>
              </div>
              <div class="flex items-center space-x-2">
                <%= if @google_connected and @hubspot_connected do %>
                  <span class="px-3 py-1 text-xs font-medium text-green-700 bg-green-100 rounded-full">
                    All Connected
                  </span>
                <% else %>
                  <span class="px-3 py-1 text-xs font-medium text-yellow-700 bg-yellow-100 rounded-full">
                    Partial Setup
                  </span>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Messages with Enhanced Styling -->
          <div class="flex-1 overflow-y-auto p-6 space-y-6" id="messages" phx-update="stream">
            <%= for {id, message} <- @streams.messages do %>
              <div
                id={id}
                class={"flex space-x-3 animate-fade-in #{if message.role == "user", do: "justify-end"}"}
              >
                <%= if message.role == "assistant" do %>
                  <div class="w-8 h-8 bg-gradient-to-br from-blue-600 to-blue-700 rounded-full flex items-center justify-center flex-shrink-0 shadow-lg">
                    <svg class="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                <% end %>

                <div class="flex-1 max-w-3xl">
                  <div class={[
                    "rounded-2xl p-4 shadow-sm",
                    if(message.role == "user",
                      do: "bg-gradient-to-br from-blue-600 to-blue-700 text-white ml-auto",
                      else: "bg-white text-gray-800 border border-gray-200"
                    )
                  ]}>
                    <p class="whitespace-pre-wrap leading-relaxed">{message.content}</p>
                  </div>
                  <p class="text-xs text-gray-500 mt-2 flex items-center">
                    <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                      <path
                        fill-rule="evenodd"
                        d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z"
                        clip-rule="evenodd"
                      />
                    </svg>
                    {Calendar.strftime(message.inserted_at, "%I:%M %p")}
                  </p>
                </div>

                <%= if message.role == "user" do %>
                  <div class="w-8 h-8 bg-gradient-to-br from-gray-400 to-gray-500 rounded-full flex-shrink-0 shadow-lg">
                  </div>
                <% end %>
              </div>
            <% end %>
            
    <!-- Typing Indicator -->
            <%= if @is_typing do %>
              <div class="flex space-x-3 animate-pulse">
                <div class="w-8 h-8 bg-gradient-to-br from-blue-600 to-blue-700 rounded-full flex items-center justify-center flex-shrink-0">
                  <svg class="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </div>
                <div class="bg-white border border-gray-200 rounded-2xl p-4 shadow-sm">
                  <div class="flex space-x-1">
                    <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></div>
                    <div
                      class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"
                      style="animation-delay: 0.1s"
                    >
                    </div>
                    <div
                      class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"
                      style="animation-delay: 0.2s"
                    >
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
          
    <!-- Enhanced Input Area -->
          <div class="border-t border-gray-200 p-4 bg-white shadow-lg">
            <.form
              for={@message_form}
              phx-submit="send_message"
              id="message-form"
              class="flex space-x-3"
            >
              <div class="flex-1 relative">
                <.input
                  field={@message_form[:content]}
                  type="text"
                  placeholder="Ask me about clients, schedule meetings, or give me tasks..."
                  class="w-full border border-gray-300 rounded-xl px-4 py-3 pr-12 focus:ring-2 focus:ring-blue-500 focus:border-transparent text-gray-900 placeholder-gray-500 bg-white shadow-sm transition-all duration-200"
                  autocomplete="off"
                />
              </div>
              <button
                type="submit"
                class="px-6 py-3 bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-700 hover:to-blue-800 text-white rounded-xl transition-all duration-200 shadow-lg hover:shadow-xl transform hover:scale-105"
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
            <p class="text-xs text-gray-500 mt-3 flex items-center justify-center">
              <%= if @google_connected and @hubspot_connected do %>
                <svg class="w-3 h-3 mr-1 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                    clip-rule="evenodd"
                  />
                </svg>
                Connected to Gmail, Calendar, and HubSpot • AI Agent Ready
              <% else %>
                <svg class="w-3 h-3 mr-1 text-yellow-500" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                    clip-rule="evenodd"
                  />
                </svg>
                Connect your accounts above to unlock full AI capabilities
              <% end %>
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

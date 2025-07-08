defmodule FinancialAdvisorAiWeb.ChatLive do
  use FinancialAdvisorAiWeb, :live_view

  require Logger
  alias FinancialAdvisorAi.AI

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      user_id = socket.assigns.current_scope.user.id

      Phoenix.PubSub.subscribe(
        FinancialAdvisorAi.PubSub,
        "chat:#{user_id}"
      )

      # Subscribe to agent proactive actions
      Phoenix.PubSub.subscribe(
        FinancialAdvisorAi.PubSub,
        "agent:#{user_id}"
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
     |> assign(:editing_conversation_id, nil)
     |> assign(:editing_title, nil)
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

    # Immediately clear input and show typing indicator, then process LLM in background
    send(self(), {:process_llm_response, content, user_id, conversation_id})
    Process.send_after(self(), :force_rerender, 10)

    {:noreply,
     socket
     |> assign(:message_form, to_form(%{"content" => ""}))
     |> assign(:is_typing, true)}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    {:ok, conversation} =
      AI.create_conversation(%{
        title: "New Conversation",
        user_id: user_id
      })

    conversations = AI.list_conversations(user_id)
    messages = AI.list_messages(conversation.id)

    {:noreply,
     socket
     |> assign(:conversations, conversations)
     |> assign(:active_conversation, conversation)
     |> assign(:messages, messages)
     |> stream(:messages, messages, reset: true)}
  end

  @impl true
  def handle_event("switch_conversation", %{"conversation_id" => conversation_id}, socket) do
    conversation = AI.get_conversation!(conversation_id)
    messages = AI.list_messages(conversation_id)

    {:noreply,
     socket
     |> assign(:active_conversation, conversation)
     |> assign(:messages, messages)
     |> stream(:messages, messages, reset: true)}
  end

  @impl true
  def handle_event("start_rename", %{"conversation_id" => conversation_id}, socket) do
    conversation = AI.get_conversation!(conversation_id)

    {:noreply,
     socket
     |> assign(:editing_conversation_id, conversation_id)
     |> assign(:editing_title, conversation.title)}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_conversation_id, nil)
     |> assign(:editing_title, nil)}
  end

  @impl true
  def handle_event(
        "save_rename",
        %{"conversation_id" => conversation_id, "title" => title},
        socket
      ) do
    conversation = AI.get_conversation!(conversation_id)

    case AI.update_conversation(conversation, %{title: title}) do
      {:ok, updated_conversation} ->
        user_id = socket.assigns.current_scope.user.id
        conversations = AI.list_conversations(user_id)

        socket =
          socket
          |> assign(:conversations, conversations)
          |> assign(:editing_conversation_id, nil)
          |> assign(:editing_title, nil)

        socket =
          if socket.assigns.active_conversation.id == conversation_id do
            assign(socket, :active_conversation, updated_conversation)
          else
            socket
          end

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_conversation", %{"conversation_id" => conversation_id}, socket) do
    conversation = AI.get_conversation!(conversation_id)
    user_id = socket.assigns.current_scope.user.id

    case AI.delete_conversation(conversation) do
      {:ok, _} ->
        conversations = AI.list_conversations(user_id)

        # If we deleted the active conversation, switch to the first available one or create a new one
        {active_conversation, messages} =
          case conversations do
            [first_conversation | _] ->
              {first_conversation, AI.list_messages(first_conversation.id)}

            [] ->
              {:ok, new_conversation} =
                AI.create_conversation(%{
                  title: "New Conversation",
                  user_id: user_id
                })

              {new_conversation, []}
          end

        # Refresh conversations list to include the potentially new conversation
        conversations = AI.list_conversations(user_id)

        {:noreply,
         socket
         |> assign(:conversations, conversations)
         |> assign(:active_conversation, active_conversation)
         |> assign(:messages, messages)
         |> stream(:messages, messages, reset: true)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("disconnect_hubspot", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case AI.get_integration(user_id, "hubspot") do
      nil ->
        {:noreply, socket}

      integration ->
        case AI.delete_integration(integration) do
          {:ok, _} ->
            {:noreply, assign(socket, :hubspot_connected, false)}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("update_message", %{"content" => content}, socket) do
    {:noreply, assign(socket, :message_form, to_form(%{"content" => content}))}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("timezone_detected", %{"timezone" => timezone}, socket) do
    user_id = socket.assigns.current_scope.user.id
    user = socket.assigns.current_scope.user

    # Update user's timezone if it's different from the detected one
    if user.timezone != timezone do
      case FinancialAdvisorAi.Accounts.update_user_timezone(user, %{timezone: timezone}) do
        {:ok, updated_user} ->
          Logger.info("Updated user #{user_id} timezone to #{timezone}")
          {:noreply, put_in(socket.assigns.current_scope.user, updated_user)}

        {:error, reason} ->
          Logger.warning("Failed to update user timezone: #{inspect(reason)}")
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  @impl true
  def handle_info({:proactive_action, action}, socket) do
    # Handle proactive agent actions
    Logger.info("Agent proactive action: #{String.slice(action, 0, 100)}...")

    # Create a system message to show the proactive action
    {:ok, system_message} =
      AI.create_message(%{
        conversation_id: socket.assigns.active_conversation.id,
        role: "assistant",
        content: "🤖 **Proactive Action**: #{action}"
      })

    # Broadcast the system message
    Phoenix.PubSub.broadcast(
      FinancialAdvisorAi.PubSub,
      "chat:#{socket.assigns.current_scope.user.id}",
      {:new_message, system_message}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:process_llm_response, content, user_id, conversation_id}, socket) do
    # Use the Agent system to process the message
    ai_response =
      case FinancialAdvisorAi.AI.Agent.process_message(user_id, content, conversation_id) do
        {:ok, response} ->
          response

        {:error, reason} ->
          Logger.error("Agent failed to process message: #{inspect(reason)}")
          generate_fallback_response(content, %{emails: [], contacts: []})
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

    {:noreply, assign(socket, :is_typing, false)}
  end

  @impl true
  def handle_info(:force_rerender, socket) do
    {:noreply, socket}
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
          |> Enum.map_join("\n\n", fn {email, index} ->
            preview = String.slice(email.content_preview, 0, 150)

            "**#{index}. #{extract_name(email.sender)}** (#{email.sender})\n   📧 #{email.subject}\n   💬 \"#{preview}...\"\n   📅 #{format_date(email.date)}"
          end)

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
          |> Enum.map_join("\n\n", fn {email, index} ->
            preview = String.slice(email.content_preview, 0, 150)

            "**#{index}. #{extract_name(email.sender)}** (#{email.sender})\n   📧 #{email.subject}\n   💬 \"#{preview}...\"\n   📅 #{format_date(email.date)}"
          end)

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
          |> Enum.map_join("\n\n", fn {email, index} ->
            preview = String.slice(email.content_preview, 0, 150)

            "**#{index}. #{extract_name(email.sender)}** (#{email.sender})\n   📧 #{email.subject}\n   💬 \"#{preview}...\"\n   📅 #{format_date(email.date)}"
          end)

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

        email_preview = get_top_emails(emails)

        "🔍 **Search Results for:** \"#{question}\"\n\nI found #{summary_parts} that might be relevant.#{email_preview}\n\n💡 **To get more detailed analysis:**\n• Connect your accounts for full AI processing\n• Ask more specific questions\n• Try different search terms\n\n🤖 **I'm here to help with:** client management, scheduling, email analysis, and task automation!"
    end
  end

  defp get_top_emails(emails) do
    emails
    |> Enum.take(3)
    |> Enum.map_join("\n", fn email ->
      "• #{extract_name(email.sender)}: #{email.subject}"
    end)
  end

  # Helper functions for better formatting
  defp extract_name(email) do
    case String.split(email, "@") do
      [name | _] ->
        name
        |> String.split(".")
        |> Enum.map_join(" ", &String.capitalize/1)

      _ ->
        email
    end
  end

  defp format_date(date) when is_struct(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  defp format_date(_), do: "Recent"

  defp format_message_time(utc_time, user_timezone) when user_timezone == "UTC" do
    Calendar.strftime(utc_time, "%I:%M %p")
  end

  defp format_message_time(utc_time, user_timezone) do
    # Use proper timezone conversion with DST support
    case DateTime.shift_zone(utc_time, user_timezone) do
      {:ok, user_time} ->
        Calendar.strftime(user_time, "%I:%M %p")

      {:error, _} ->
        # Fallback to UTC if timezone conversion fails
        Calendar.strftime(utc_time, "%I:%M %p")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="app-container" phx-hook="TimezoneDetector" id="timezone-detector">
        <!-- Sidebar -->
        <div class="sidebar">
          <!-- Header -->
          <div class="p-4 border-b border-gray-600 bg-gradient-to-r from-gray-800 to-gray-700">
            <div class="text-center">
              <h1 class="text-white text-lg font-bold financial-text-gradient">
                Financial Advisor AI
              </h1>
              <p class="text-gray-300 text-xs mt-1">Your AI Assistant</p>
            </div>
          </div>
          <div class="flex-1 overflow-y-auto p-3 space-y-2">
            <!-- New Chat Button - Metallic Style -->
            <button
              phx-click="new_conversation"
              class="w-full flex items-center justify-center space-x-2 px-4 py-3 mb-4 text-sm font-medium text-gray-800 financial-metallic-accent hover:shadow-lg transition-all duration-200 rounded-lg"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                />
              </svg>
              <span>New Chat</span>
            </button>

            <%= for conversation <- @conversations do %>
              <div class={"financial-sidebar-item p-3 cursor-pointer #{if conversation.id == @active_conversation.id, do: "active", else: ""}"}>
                <%= if @editing_conversation_id == conversation.id do %>
                  <form
                    phx-submit="save_rename"
                    phx-value-conversation_id={conversation.id}
                    class="flex items-center space-x-2"
                  >
                    <input
                      type="text"
                      name="title"
                      value={@editing_title}
                      class="flex-1 text-sm font-medium text-gray-200 financial-input rounded px-2 py-1"
                      autofocus
                    />
                    <button type="submit" class="text-green-400 hover:text-green-300">
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M5 13l4 4L19 7"
                        />
                      </svg>
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_rename"
                      class="text-gray-400 hover:text-gray-300"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                    </button>
                  </form>
                <% else %>
                  <div
                    phx-click="switch_conversation"
                    phx-value-conversation_id={conversation.id}
                    class="flex items-center justify-between group"
                  >
                    <div class="flex-1 min-w-0">
                      <h3 class="font-medium text-gray-200 text-sm truncate">{conversation.title}</h3>
                      <p class="text-xs text-gray-400 mt-1">
                        {Calendar.strftime(conversation.updated_at, "%b %d")}
                      </p>
                    </div>
                    <div class="flex space-x-1 opacity-0 group-hover:opacity-100 transition-opacity">
                      <button
                        phx-click="start_rename"
                        phx-value-conversation_id={conversation.id}
                        class="text-gray-500 hover:text-gray-300 p-1"
                        title="Rename"
                      >
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
                          />
                        </svg>
                      </button>
                      <button
                        phx-click="delete_conversation"
                        phx-value-conversation_id={conversation.id}
                        class="text-gray-500 hover:text-red-400 p-1"
                        title="Delete"
                        data-confirm="Are you sure you want to delete this conversation?"
                      >
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                          />
                        </svg>
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
          <div class="p-4 border-t border-gray-600 bg-gray-800">
            <h4 class="text-sm font-semibold text-gray-200 mb-4 flex items-center">
              <svg class="w-4 h-4 mr-2 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path d="M13 6a3 3 0 11-6 0 3 3 0 016 0zM18 8a2 2 0 11-4 0 2 2 0 014 0zM14 15a4 4 0 00-8 0v3h8v-3z" />
              </svg>
              Connected Services
            </h4>
            <div class="space-y-3">
              <div class="flex items-center justify-between p-3 rounded-lg financial-card">
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 rounded-full bg-orange-500 bg-opacity-20 flex items-center justify-center">
                    <svg class="w-4 h-4 text-orange-400" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" />
                    </svg>
                  </div>
                  <span class="text-sm font-medium text-gray-200">HubSpot CRM</span>
                </div>
                <%= if @hubspot_connected do %>
                  <div class="flex items-center space-x-2">
                    <span class="financial-status-badge">
                      Connected
                    </span>
                    <div class="tooltip">
                      <button
                        phx-click="disconnect_hubspot"
                        class="p-1 text-red-400 hover:text-red-300 hover:bg-red-500 hover:bg-opacity-10 rounded-full transition-colors"
                        data-confirm="Are you sure you want to disconnect HubSpot?"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M6 18L18 6M6 6l12 12"
                          />
                        </svg>
                      </button>
                      <span class="tooltiptext">Disconnect</span>
                    </div>
                  </div>
                <% else %>
                  <a
                    href="/auth/hubspot"
                    class="px-3 py-1 text-xs font-medium text-gray-200 bg-gray-600 bg-opacity-30 hover:bg-opacity-50 rounded-full transition-colors border border-gray-500 border-opacity-30"
                  >
                    Connect
                  </a>
                <% end %>
              </div>
            </div>
            <%= unless @hubspot_connected do %>
              <div class="mt-4 p-3 bg-gradient-to-r from-gray-600 from-opacity-10 to-gray-500 to-opacity-10 rounded-lg border border-gray-500 border-opacity-30">
                <p class="text-xs text-gray-300 font-semibold mb-2">🚀 Get Started</p>
                <p class="text-xs text-gray-300">
                  Connect your HubSpot account to unlock the full power of your AI assistant!
                </p>
              </div>
            <% end %>
            
    <!-- Logout Button -->
            <div class="mt-4 pt-4 border-t border-gray-600">
              <.link
                href={~p"/users/log-out"}
                method={:delete}
                class="w-full flex items-center justify-center space-x-2 px-4 py-2 text-sm font-medium text-gray-300 financial-card hover:text-gray-200 transition-colors"
                data-confirm="Are you sure you want to log out?"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                  />
                </svg>
                <span>Logout</span>
              </.link>
            </div>
          </div>
        </div>
        <!-- Chat Area -->
        <div class="chat-area">
          <!-- Chat Header with Status -->
          <div class="px-6 py-4 border-b border-gray-600 bg-gray-800 shadow-lg">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-semibold text-gray-200">{@active_conversation.title}</h2>
                <p class="text-sm text-gray-400">
                  AI agent ready to help with your financial advisory tasks
                </p>
              </div>
              <div class="flex items-center space-x-2">
                <%= if @hubspot_connected do %>
                  <span class="financial-status-badge">
                    All Connected
                  </span>
                <% else %>
                  <span class="financial-status-badge partial">
                    Partial Setup
                  </span>
                <% end %>
              </div>
            </div>
          </div>
          <!-- Messages -->
          <div
            class="chat-messages space-y-6"
            id="messages"
            phx-update="stream"
            phx-hook="ChatAutoScroll"
          >
            <%= for {id, message} <- @streams.messages do %>
              <div
                id={id}
                class={"flex space-x-3 animate-fade-in #{if message.role == "user", do: "justify-end"}"}
              >
                <%= if message.role == "assistant" do %>
                  <div class="w-8 h-8 financial-gradient rounded-full flex items-center justify-center flex-shrink-0 shadow-lg">
                    <svg class="w-4 h-4 text-gray-800" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                <% end %>
                <div class="flex-1 max-w-3xl">
                  <div class={[
                    "p-4 shadow-sm",
                    if(message.role == "user",
                      do: "financial-message-bubble user text-gray-200 ml-auto",
                      else: "financial-message-bubble text-gray-200"
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
                    {format_message_time(message.inserted_at, @current_scope.user.timezone || "UTC")}
                  </p>
                </div>
                <%= if message.role == "user" do %>
                  <div class="w-8 h-8 bg-gradient-to-br from-gray-500 to-gray-600 rounded-full flex-shrink-0 shadow-lg">
                  </div>
                <% end %>
              </div>
            <% end %>
            <!-- Typing Indicator -->
            <%= if @is_typing do %>
              <div class="flex space-x-3">
                <div class="w-8 h-8 financial-gradient rounded-full flex items-center justify-center flex-shrink-0">
                  <svg class="w-4 h-4 text-gray-800" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </div>
                <div class="financial-typing-indicator p-4">
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
          <!-- Input Area -->
          <div class="border-t border-gray-600 bg-gray-800 shadow-lg">
            <div class="chat-input-area">
              <.form
                for={@message_form}
                phx-submit="send_message"
                phx-change="update_message"
                id="message-form"
                class="flex space-x-3"
              >
                <div class="flex-1 relative">
                  <.input
                    field={@message_form[:content]}
                    type="text"
                    placeholder="Ask me about clients, schedule meetings, or give me tasks..."
                    class="w-full financial-input rounded-xl px-4 py-3 pr-12 focus:ring-2 focus:ring-gray-500 focus:border-transparent shadow-sm transition-all duration-200"
                    autocomplete="off"
                  />
                </div>
                <button
                  type="submit"
                  class="px-6 py-3 financial-metallic-accent hover:shadow-xl text-gray-800 rounded-xl transition-all duration-200 transform hover:scale-105"
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
                  <svg class="w-3 h-3 mr-1 text-green-400" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  Connected to Gmail, Calendar, and HubSpot • AI Agent Ready
                <% else %>
                  <svg class="w-3 h-3 mr-1 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
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
      </div>
    </Layouts.app>
    """
  end
end

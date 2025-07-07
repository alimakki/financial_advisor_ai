defmodule FinancialAdvisorAi.AI.LlmService do
  @moduledoc """
  LLM service for generating AI responses using OpenAI API.
  Handles chat completions, tool calling, and context management.
  """

  require Logger
  # alias FinancialAdvisorAi.Repo
  alias FinancialAdvisorAi.Integrations.CalendarService

  # @openai_api_url "https://api.openai.com/v1"
  @default_model "gpt-4o-mini"
  @embeddings_model "text-embedding-3-small"

  @doc """
  Generates an AI response based on user question and RAG context.
  """
  def generate_response(user_question, rag_context, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)

    system_prompt = build_system_prompt()
    # build_user_prompt(user_question, rag_context)
    user_prompt = user_question

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]

    case make_openai_request(messages, model) do
      {:ok, %{"choices" => [choice]}} ->
        content = choice["message"]["content"] |> strip_think_tags()
        {:ok, content || "I apologize, but I couldn't generate a response at this time."}

      {:error, reason} ->
        Logger.warning("OpenAI API error: #{inspect(reason)}")
        {:error, reason, fallback_response(user_question, rag_context)}
    end
  end

  @doc """
  Generates a response with tool calling capabilities for task execution.
  """
  def generate_response_with_tools(user_question, rag_context, user_id, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)

    system_prompt = build_system_prompt_with_tools()
    # build_user_prompt(user_question, rag_context)
    user_prompt = user_question

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]

    tools = build_tool_definitions()

    case make_openai_request_with_tools(messages, model, tools) do
      {:ok, response} ->
        case parse_tool_response(response, user_id, rag_context) do
          {:ok, content} -> {:ok, strip_think_tags(content)}
          other -> other
        end

      {:error, reason} ->
        Logger.warning("OpenAI API with tools error: #{inspect(reason)}")
        {:error, reason, fallback_response(user_question, rag_context)}
    end
  end

  def create_embedding(text_data) do
    make_embedding_request(text_data, @embeddings_model)
  end

  # Private functions

  defp build_system_prompt do
    """
    You are an AI Financial Advisor Assistant. You help financial advisors with:

    1. Answering questions about clients based on email communications and CRM data
    2. Scheduling appointments and managing calendar events
    3. Creating and managing contacts in HubSpot CRM
    4. Sending emails on behalf of the advisor
    5. Providing insights and analysis based on available data

    You have access to:
    - Email communications (via Gmail integration)
    - Calendar events (via Google Calendar integration)
    - CRM contacts and notes (via HubSpot integration)

    Be professional, helpful, and accurate. When you don't have enough information to answer a question,
    say so clearly and suggest ways to get the needed information.

    For questions about specific people or events, always reference the available context data.
    """
  end

  defp build_system_prompt_with_tools do
    """
    You are an AI Financial Advisor Assistant with tool calling capabilities. You can:

    1. Search and analyze email communications
    2. Schedule calendar appointments
    3. Create and update CRM contacts
    4. Send emails
    5. Create and manage tasks

    Available tools:
    - search_emails: Search through emails for specific content or people
    - schedule_meeting: Schedule a calendar appointment with clients
    - create_contact: Create a new contact in the CRM
    - send_email: Send an email to a client or contact
    - create_task: Create a persistent task for follow-up

    When a user requests an action that requires tool usage, use the appropriate tools to complete the task.
    Always explain what you're doing and ask for confirmation before taking significant actions.
    Be conversational and helpful while being thorough in your explanations.
    """
  end

  # defp build_user_prompt(user_question, rag_context) do
  #   context_section = build_context_section(rag_context)

  #   """
  #   User Question: #{user_question}

  #   Available Context:
  #   #{context_section}

  #   Please provide a helpful response based on the available context. If the user is asking you to
  #   perform an action (like scheduling a meeting, sending an email, etc.), use the appropriate tools
  #   to complete the task. Always explain what you're doing.
  #   """
  # end

  # defp build_context_section(%{emails: emails, contacts: contacts}) do
  #   cond do
  #     (emails == [] or is_nil(emails)) and (contacts == [] or is_nil(contacts)) ->
  #       "No relevant emails or contacts found for this query."

  #     true ->
  #       [build_email_context(emails), build_contact_context(contacts)]
  #       |> Enum.reject(&(&1 == ""))
  #       |> Enum.join("")
  #   end
  # end

  # defp build_email_context([]), do: ""

  # defp build_email_context(emails) do
  #   email_summaries =
  #     Enum.map_join("\n", emails, fn email ->
  #       "- From: #{email.sender}\n  Subject: #{email.subject}\n  Preview: #{email.content_preview}"
  #     end)

  #   "Relevant Emails:\n#{email_summaries}"
  # end

  # defp build_contact_context([]), do: ""

  # defp build_contact_context(contacts) do
  #   contact_summaries =
  #     Enum.map_join("\n", contacts, fn contact ->
  #       "- #{contact.name} (#{contact.email}): #{contact.message_count} messages"
  #     end)

  #   "\nRelevant Contacts:\n#{contact_summaries}"
  # end

  defp openai_api_url do
    System.get_env("OPENAI_BASE_URL") ||
      Application.get_env(:financial_advisor_ai, :openai_api_url)
  end

  defp make_openai_request(messages, model) do
    api_key = get_api_key()

    if is_nil(api_key) do
      {:error, :no_api_key}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: model,
        messages: messages,
        max_tokens: 1000,
        temperature: 0.7
      }

      case Req.post("#{openai_api_url()}/chat/completions", headers: headers, json: body) do
        {:ok, %{status: 200, body: response}} -> {:ok, response}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp make_embedding_request(text_data, model) do
    api_key = get_api_key()

    if is_nil(api_key) do
      {:error, :no_api_key}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: model,
        input: text_data
      }

      case Req.post("#{openai_api_url()}/embeddings", headers: headers, json: body) do
        {:ok, %{status: 200, body: response}} -> {:ok, response}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp make_openai_request_with_tools(messages, model, tools) do
    api_key = get_api_key()

    if is_nil(api_key) do
      {:error, :no_api_key}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: model,
        messages: messages,
        tools: tools,
        tool_choice: "auto",
        max_tokens: 1000,
        temperature: 0.7
      }

      case Req.post("#{openai_api_url()}/chat/completions", headers: headers, json: body) do
        {:ok, %{status: 200, body: response}} -> {:ok, response}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp build_tool_definitions do
    [
      %{
        type: "function",
        function: %{
          name: "search_emails",
          description: "Search through emails for specific content, people, or topics",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "The search query to find relevant emails"
              },
              sender: %{
                type: "string",
                description: "Optional: filter by sender email address"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "schedule_meeting",
          description: "Schedule a calendar appointment with a client",
          parameters: %{
            type: "object",
            properties: %{
              client_email: %{
                type: "string",
                description: "The email address of the client to schedule with"
              },
              subject: %{
                type: "string",
                description: "The meeting subject/title"
              },
              duration_minutes: %{
                type: "integer",
                description: "Meeting duration in minutes (default 60)"
              },
              preferred_times: %{
                type: "array",
                items: %{type: "string"},
                description: "List of preferred meeting times to suggest"
              }
            },
            required: ["client_email", "subject"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "send_email",
          description: "Send an email to a client or contact",
          parameters: %{
            type: "object",
            properties: %{
              to: %{
                type: "string",
                description: "The recipient's email address"
              },
              subject: %{
                type: "string",
                description: "The email subject line"
              },
              body: %{
                type: "string",
                description: "The email body content"
              }
            },
            required: ["to", "subject", "body"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_contact",
          description: "Create a new contact in the CRM system",
          parameters: %{
            type: "object",
            properties: %{
              name: %{
                type: "string",
                description: "The contact's full name"
              },
              email: %{
                type: "string",
                description: "The contact's email address"
              },
              notes: %{
                type: "string",
                description: "Initial notes about the contact"
              }
            },
            required: ["name", "email"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_task",
          description: "Create a persistent task for follow-up actions",
          parameters: %{
            type: "object",
            properties: %{
              title: %{
                type: "string",
                description: "The task title"
              },
              description: %{
                type: "string",
                description: "Detailed task description"
              },
              task_type: %{
                type: "string",
                description: "Type of task (email, calendar, hubspot, follow_up)"
              },
              scheduled_for: %{
                type: "string",
                description: "When to execute the task (ISO 8601 format)"
              }
            },
            required: ["title", "task_type"]
          }
        }
      }
    ]
  end

  defp parse_tool_response(response, user_id, rag_context) do
    choice = get_in(response, ["choices", Access.at(0)])
    message = get_in(choice, ["message"])

    case get_in(message, ["tool_calls"]) do
      nil ->
        # No tool calls, return regular content
        content = get_in(message, ["content"])
        {:ok, content || "I apologize, but I couldn't generate a response at this time."}

      tool_calls ->
        # Process tool calls
        results = execute_tool_calls(tool_calls, user_id)
        format_tool_results(results, rag_context)
    end
  end

  defp execute_tool_calls(tool_calls, user_id) do
    Enum.map(tool_calls, fn tool_call ->
      function_name = get_in(tool_call, ["function", "name"])
      arguments = get_in(tool_call, ["function", "arguments"])

      case Jason.decode(arguments) do
        {:ok, params} ->
          execute_tool(function_name, params, user_id)

        {:error, _} ->
          {:error, "Invalid tool arguments"}
      end
    end)
  end

  defp execute_tool("search_emails", params, user_id) do
    query = Map.get(params, "query")
    sender = Map.get(params, "sender")

    # Use our existing RAG service
    context = FinancialAdvisorAi.AI.RagService.search_context(user_id, query)

    filtered_emails =
      if sender do
        Enum.filter(context.emails, fn email -> String.contains?(email.sender, sender) end)
      else
        context.emails
      end

    {:ok, %{tool: "search_emails", results: filtered_emails, query: query}}
  end

  defp execute_tool("schedule_meeting", params, user_id) do
    client_email = Map.get(params, "client_email")
    subject = Map.get(params, "subject")
    duration_minutes = Map.get(params, "duration_minutes", 60)

    # Use Calendar service to actually schedule the meeting
    case CalendarService.schedule_meeting_with_client(
           user_id,
           client_email,
           subject,
           duration_minutes
         ) do
      {:ok, event} ->
        {:ok,
         %{
           tool: "schedule_meeting",
           event_id: event.id,
           status: "scheduled",
           start_time: event.start_time,
           end_time: event.end_time,
           attendees: event.attendees
         }}

      {:error, :not_connected} ->
        # Create a task for manual scheduling
        task_params = %{
          user_id: user_id,
          title: "Schedule meeting: #{subject}",
          description: "Schedule meeting with #{client_email}",
          task_type: "calendar",
          parameters: params
        }

        case FinancialAdvisorAi.AI.create_task(task_params) do
          {:ok, task} ->
            {:ok, %{tool: "schedule_meeting", task_id: task.id, status: "task_created"}}

          {:error, reason} ->
            {:error, "Failed to create scheduling task: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to schedule meeting: #{inspect(reason)}"}
    end
  end

  defp execute_tool("send_email", params, user_id) do
    # Create a task for sending the email
    task_params = %{
      user_id: user_id,
      title: "Send email: #{Map.get(params, "subject")}",
      description: "Send email to #{Map.get(params, "to")}",
      task_type: "email",
      parameters: params
    }

    case FinancialAdvisorAi.AI.create_task(task_params) do
      {:ok, task} ->
        {:ok, %{tool: "send_email", task_id: task.id, status: "task_created"}}

      {:error, reason} ->
        {:error, "Failed to create email task: #{inspect(reason)}"}
    end
  end

  defp execute_tool("create_contact", params, user_id) do
    # Create a task for creating the contact
    task_params = %{
      user_id: user_id,
      title: "Create contact: #{Map.get(params, "name")}",
      description: "Create contact for #{Map.get(params, "email")}",
      task_type: "hubspot",
      parameters: params
    }

    case FinancialAdvisorAi.AI.create_task(task_params) do
      {:ok, task} ->
        {:ok, %{tool: "create_contact", task_id: task.id, status: "task_created"}}

      {:error, reason} ->
        {:error, "Failed to create contact task: #{inspect(reason)}"}
    end
  end

  defp execute_tool("create_task", params, user_id) do
    task_params = Map.put(params, "user_id", user_id)

    case FinancialAdvisorAi.AI.create_task(task_params) do
      {:ok, task} ->
        {:ok, %{tool: "create_task", task_id: task.id, status: "task_created"}}

      {:error, reason} ->
        {:error, "Failed to create task: #{inspect(reason)}"}
    end
  end

  defp execute_tool(unknown_tool, _params, _user_id) do
    {:error, "Unknown tool: #{unknown_tool}"}
  end

  defp format_tool_results(results, _rag_context) do
    successful_results = Enum.filter(results, fn {status, _} -> status == :ok end)
    error_results = Enum.filter(results, fn {status, _} -> status == :error end)

    response_parts =
      successful_results
      |> Enum.map(fn {:ok, result} -> format_success_result(result) end)
      |> Kernel.++(
        Enum.map(error_results, fn {:error, message} -> format_error_result(message) end)
      )

    final_response = Enum.join(response_parts, "\n\n")
    {:ok, final_response}
  end

  defp format_success_result(%{tool: "search_emails", results: results, query: query}) do
    if length(results) > 0 do
      email_summaries =
        Enum.map_join("\n", results, fn email ->
          "• #{email.sender}: #{email.subject}"
        end)

      "Found #{length(results)} emails for '#{query}':\n#{email_summaries}"
    else
      "No emails found for '#{query}'"
    end
  end

  defp format_success_result(%{tool: "schedule_meeting", status: "scheduled"} = result) do
    "✅ Meeting scheduled successfully! Event ID: #{result.event_id}\nTime: #{result.start_time} - #{result.end_time}"
  end

  defp format_success_result(%{
         tool: "schedule_meeting",
         status: "task_created",
         task_id: task_id
       }) do
    "✅ Created scheduling task (ID: #{task_id}). I'll work on coordinating the meeting."
  end

  defp format_success_result(%{tool: "send_email", task_id: task_id}) do
    "✅ Created email task (ID: #{task_id}). I'll send the email for you."
  end

  defp format_success_result(%{tool: "create_contact", task_id: task_id}) do
    "✅ Created contact creation task (ID: #{task_id}). I'll add them to your CRM."
  end

  defp format_success_result(%{tool: "create_task", task_id: task_id}) do
    "✅ Created task (ID: #{task_id}) for follow-up."
  end

  defp format_success_result(_), do: ""

  defp format_error_result(message), do: "❌ Error: #{message}"

  defp get_api_key do
    System.get_env("OPENAI_API_KEY") ||
      Application.get_env(:financial_advisor_ai, :openai_api_key)
  end

  defp fallback_response(user_question, rag_context) do
    case {rag_context.emails, rag_context.contacts} do
      {[], []} ->
        "I understand you're asking: \"#{user_question}\"\n\nI'm your AI Financial Advisor assistant, ready to help! Once you connect your accounts and I have access to your emails and CRM data, I'll be able to provide much more detailed and contextual responses."

      {emails, contacts} ->
        email_count = length(emails)
        contact_count = length(contacts)

        "Based on your question \"#{user_question}\", I found #{email_count} relevant emails and #{contact_count} related contacts. However, I'm currently unable to connect to the AI service to provide a detailed analysis. Please try again in a moment, or feel free to ask a more specific question about the information you're looking for."
    end
  end

  # Utility function to strip <think>...</think> blocks from LLM output
  defp strip_think_tags(text) when is_binary(text) do
    Regex.replace(~r/<think>[\s\S]*?<\/think>/, text, "")
    |> String.trim()
  end

  defp strip_think_tags(text), do: text
end

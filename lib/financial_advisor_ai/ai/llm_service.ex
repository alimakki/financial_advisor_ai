defmodule FinancialAdvisorAi.AI.LlmService do
  @moduledoc """
  LLM service for generating AI responses using OpenAI API.
  Handles chat completions, tool calling, and context management.
  """

  require Logger
  # alias FinancialAdvisorAi.Repo
  alias FinancialAdvisorAi.Integrations.{CalendarService, HubspotService}

  # @openai_api_url "https://api.openai.com/v1"
  @default_model "gpt-4o"
  @embeddings_model "text-embedding-3-small"
  @doc """
  Generates an AI response based on user question and RAG context.
  Now always uses tool calling by default.
  """
  def generate_response(user_question, rag_context, user_id, opts \\ []) do
    generate_response_with_tools(user_question, rag_context, user_id, opts)
  end

  @doc """
  Generates an AI response without tool calling capabilities.
  Use this for simple responses that don't need tool execution.
  """
  def generate_response_without_tools(user_question, rag_context, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)

    system_prompt = build_system_prompt()

    # Build messages with conversation history
    messages = build_messages_with_history(system_prompt, user_question, rag_context)

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
    # get timezone from user
    user = FinancialAdvisorAi.Accounts.get_user!(user_id)
    timezone = user.timezone

    model = Keyword.get(opts, :model, @default_model)

    system_prompt = build_system_prompt_with_tools(timezone)

    # Build initial messages with conversation history
    initial_messages = build_messages_with_history(system_prompt, user_question, rag_context)

    tools = build_tool_definitions()

    case make_openai_request_with_tools(initial_messages, model, tools) do
      {:ok, response} ->
        case parse_tool_response(response, user_id, rag_context, initial_messages) do
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

  defp build_system_prompt_with_tools(timezone) do
    current_date = Date.utc_today() |> Date.to_string()

    available_tools =
      tool_descriptions()
      |> Enum.map_join("\n", fn %{name: name, description: description} ->
        "- #{name}: #{description}"
      end)

    """
    You are an AI Financial Advisor Assistant with tool calling capabilities. You can:

    1. Search and analyze email communications
    2. Schedule calendar appointments
    3. Create and update CRM contacts
    4. Send emails
    5. Create and manage tasks

    Available tools:
    #{available_tools}

    Current date: #{current_date}
    User timezone: #{timezone}

    When a user requests an action that requires tool usage, use the appropriate tools to complete the task.
    Always explain what you're doing and ask for confirmation before taking significant actions.
    Be proactive with the tools at your disposal. For example, if a user has a message that is potentially actionable, suggest
    useful options based on the tools available, for example, if there's some sort of lead, suggest potential meeting times based on calendar availability.
    Be conversational and helpful while being thorough in your explanations.

    When working with dates and scheduling, always consider the current date (#{current_date}) to provide relevant and timely suggestions.
    """
  end

  defp build_messages_with_history(system_prompt, user_question, rag_context) do
    # Start with system prompt
    messages = [%{role: "system", content: system_prompt}]

    # Add conversation history if available
    messages =
      case Map.get(rag_context, :conversation_history) do
        nil ->
          messages

        [] ->
          messages

        history ->
          # Filter out system messages from history and convert to OpenAI format
          history_messages =
            history
            |> Enum.filter(fn msg -> msg.role in ["user", "assistant"] end)
            |> Enum.map(fn msg ->
              %{role: msg.role, content: msg.content}
            end)

          messages ++ history_messages
      end

    # Add context information if available
    messages =
      case build_context_section(rag_context) do
        "" ->
          messages

        context_info ->
          messages ++ [%{role: "system", content: "Additional context: #{context_info}"}]
      end

    # Add the current user question
    messages ++ [%{role: "user", content: user_question}]
  end

  defp build_context_section(rag_context) do
    emails = Map.get(rag_context, :emails, [])
    contacts = Map.get(rag_context, :contacts, [])
    hubspot_contacts = Map.get(rag_context, :hubspot_contacts, [])
    contact_notes = Map.get(rag_context, :contact_notes, [])

    if (emails == [] or is_nil(emails)) and
         (contacts == [] or is_nil(contacts)) and
         (hubspot_contacts == [] or is_nil(hubspot_contacts)) and
         (contact_notes == [] or is_nil(contact_notes)) do
      ""
    else
      [
        build_email_context(emails),
        build_contact_context(contacts),
        build_hubspot_contact_context(hubspot_contacts),
        build_contact_note_context(contact_notes)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end
  end

  defp build_email_context([]), do: ""

  defp build_email_context(emails) do
    email_summaries =
      Enum.map_join(emails, "\n", fn email ->
        "- From: #{email.sender}\n  Subject: #{email.subject}\n  Preview: #{email.content_preview}"
      end)

    "Relevant Emails:\n#{email_summaries}"
  end

  defp build_contact_context([]), do: ""

  defp build_contact_context(contacts) do
    contact_summaries =
      Enum.map_join(contacts, "\n", fn contact ->
        "- #{contact.name} (#{contact.email}): #{contact.message_count} messages"
      end)

    "\nRelevant Contacts:\n#{contact_summaries}"
  end

  defp build_hubspot_contact_context([]), do: ""

  defp build_hubspot_contact_context(hubspot_contacts) do
    contact_summaries =
      Enum.map_join(hubspot_contacts, "\n", fn contact ->
        company_info = if contact.company, do: " - #{contact.company}", else: ""
        "- #{contact.name} (#{contact.email})#{company_info}: #{contact.lifecycle_stage}"
      end)

    "\nRelevant HubSpot Contacts:\n#{contact_summaries}"
  end

  defp build_contact_note_context([]), do: ""

  defp build_contact_note_context(contact_notes) do
    note_summaries =
      Enum.map_join(contact_notes, "\n", fn note ->
        "- Note: #{note.content_preview}"
      end)

    "\nRelevant Contact Notes:\n#{note_summaries}"
  end

  defp openai_api_url do
    System.get_env("OPENAI_BASE_URL") ||
      Application.get_env(:financial_advisor_ai, :openai_api_url)
  end

  def make_openai_request(messages, model, additional_body_params \\ %{}) do
    api_key = get_api_key()

    if is_nil(api_key) do
      {:error, :no_api_key}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body =
        %{
          model: model,
          messages: messages,
          max_tokens: 1000,
          temperature: 0.7
        }
        |> Map.merge(additional_body_params)

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

  def make_openai_request_with_tools(messages, model, tools) do
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

  def tool_descriptions() do
    for %{function: %{name: name, description: description}} <- build_tool_definitions() do
      %{name: name, description: description}
    end
  end

  def build_tool_definitions() do
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
                description:
                  "List of preferred meeting time ranges in ISO 8601 format. Each item should be a time range like 'YYYY-MM-DDTHH:MM:SSZ/YYYY-MM-DDTHH:MM:SSZ' (start/end format). Example: ['2024-01-15T11:00:00Z/2024-01-15T12:00:00Z']"
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
              firstname: %{
                type: "string",
                description: "The contact's first name"
              },
              email: %{
                type: "string",
                description: "The contact's email address"
              }
            },
            # it is recommended to always include email, because email address is the primary unique identifier to avoid duplicate contacts in HubSpot.
            # https://developers.hubspot.com/docs/guides/api/crm/objects/contacts
            required: ["email"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "find_calendar_availability",
          description: "Find available time slots in Google Calendar for scheduling meetings",
          parameters: %{
            type: "object",
            properties: %{
              duration_minutes: %{
                type: "integer",
                description: "Duration of the meeting in minutes",
                default: 60
              },
              preferred_times: %{
                type: "array",
                items: %{
                  type: "string"
                },
                description:
                  "Preferred time ranges in format 'HH:MM-HH:MM' (e.g., ['09:00-12:00', '14:00-17:00'])",
                default: []
              },
              days_ahead: %{
                type: "integer",
                description: "Number of days ahead to search for availability",
                default: 1
              }
            },
            required: []
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "search_contacts",
          description: "Search for contacts in HubSpot CRM by name, email, or company",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "Search query to find contacts by name, email, or company"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_note",
          description: "Create a note in HubSpot CRM for a contact",
          parameters: %{
            type: "object",
            properties: %{
              contact_id: %{
                type: "string",
                description: "The HubSpot contact ID to create the note for"
              },
              note_content: %{
                type: "string",
                description: "The content of the note to create"
              }
            },
            required: ["contact_id", "note_content"]
          }
        }
      }
    ]
  end

  defp parse_tool_response(response, user_id, rag_context, initial_messages) do
    choice = get_in(response, ["choices", Access.at(0)])
    message = get_in(choice, ["message"])

    case get_in(message, ["tool_calls"]) do
      nil ->
        # No tool calls, return regular content
        content = get_in(message, ["content"])
        {:ok, content || "I apologize, but I couldn't generate a response at this time."}

      tool_calls ->
        # IO.inspect(tool_calls, label: "tool_calls")
        # Process tool calls and send results back to LLM
        execute_tool_calls_and_get_response(
          tool_calls,
          user_id,
          message,
          rag_context,
          initial_messages
        )
    end
  end

  defp execute_tool_calls_and_get_response(
         tool_calls,
         user_id,
         assistant_message,
         rag_context,
         initial_messages
       ) do
    # Execute all tool calls
    tool_results = execute_tool_calls(tool_calls, user_id)

    # Always send results to LLM, even if some tools failed
    # The LLM can handle the error messages and provide a helpful response
    send_tool_results_to_llm(
      assistant_message,
      tool_calls,
      tool_results,
      rag_context,
      initial_messages
    )
  end

  defp send_tool_results_to_llm(
         assistant_message,
         tool_calls,
         tool_results,
         rag_context,
         initial_messages
       ) do
    # Build the messages array for the follow-up request using the original context
    messages =
      initial_messages ++
        [
          %{
            role: "assistant",
            content: assistant_message["content"],
            tool_calls: format_tool_calls_for_api(tool_calls)
          }
        ]

    # Add tool result messages
    tool_messages = build_tool_result_messages(tool_calls, tool_results)
    messages = messages ++ tool_messages

    # Make follow-up request to OpenAI
    case make_openai_request(messages, @default_model) do
      {:ok, %{"choices" => [choice]}} ->
        content = choice["message"]["content"] |> strip_think_tags()
        {:ok, content || "I apologize, but I couldn't generate a response at this time."}

      {:error, reason} ->
        Logger.warning("OpenAI follow-up API error: #{inspect(reason)}")
        # Fall back to formatted tool results
        format_tool_results(tool_results, rag_context)
    end
  end

  defp format_tool_calls_for_api(tool_calls) do
    Enum.map(tool_calls, fn tool_call ->
      %{
        id: tool_call["id"],
        type: "function",
        function: %{
          name: get_in(tool_call, ["function", "name"]),
          arguments: get_in(tool_call, ["function", "arguments"])
        }
      }
    end)
  end

  defp build_tool_result_messages(tool_calls, tool_results) do
    tool_calls
    |> Enum.zip(tool_results)
    |> Enum.map(fn {tool_call, {status, result}} ->
      tool_call_id = tool_call["id"]
      function_name = get_in(tool_call, ["function", "name"])

      content =
        case status do
          :ok -> format_tool_result_for_llm(result)
          :error -> "Error: #{result}"
        end

      %{
        role: "tool",
        tool_call_id: tool_call_id,
        name: function_name,
        content: content
      }
    end)
  end

  defp format_tool_result_for_llm(result) do
    Jason.encode!(result)
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

  def execute_tool(tool_name, params, user_id)

  def execute_tool("search_emails", params, user_id) do
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

  def execute_tool("search_contacts", params, user_id) do
    query = Map.get(params, "query")

    HubspotService.search_contacts(user_id, query)
    |> case do
      {:ok, contacts} ->
        {:ok, %{tool: "search_contacts", results: contacts, query: query}}

      {:error, reason} ->
        {:error, "Failed to search contacts: #{inspect(reason)}"}
    end
  end

  def execute_tool("create_note", params, user_id) do
    contact_id = Map.get(params, "contact_id")
    note_content = Map.get(params, "note_content")

    HubspotService.create_note(user_id, contact_id, note_content)
    |> case do
      {:ok, note} ->
        {:ok, %{tool: "create_note", note_id: note.id, status: "note_created"}}

      {:error, reason} ->
        {:error, "Failed to create note: #{inspect(reason)}"}
    end
  end

  def execute_tool("schedule_meeting", params, user_id) do
    client_email = Map.get(params, "client_email")
    subject = Map.get(params, "subject")
    duration_minutes = Map.get(params, "duration_minutes", 60)
    preferred_times = Map.get(params, "preferred_times", [])

    # Use Calendar service to actually schedule the meeting
    case CalendarService.schedule_meeting_with_client(
           user_id,
           client_email,
           subject,
           duration_minutes,
           preferred_times
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

  def execute_tool("send_email", params, user_id) do
    FinancialAdvisorAi.Integrations.GmailService.send_email(
      user_id,
      params["to"],
      params["subject"],
      params["body"]
    )
    |> case do
      {:ok, _} ->
        {:ok, %{tool: "send_email", status: "email_sent"}}

      {:error, reason} ->
        {:error, "Failed to send email: #{inspect(reason)}"}
    end
  end

  def execute_tool("create_contact", params, user_id) do
    case HubspotService.create_contact(user_id, params) do
      {:ok, contact} ->
        {:ok, %{tool: "create_contact", contact_id: contact.id, status: "contact_created"}}

      {:error, {409, %{"message" => message}}} ->
        # Contact already exists - extract existing ID if possible
        existing_id = extract_existing_contact_id_from_message(message)

        {:ok,
         %{
           tool: "create_contact",
           contact_id: existing_id,
           status: "contact_already_exists",
           message: "Contact already exists in HubSpot"
         }}

      {:error, reason} ->
        {:error, "Failed to create contact: #{inspect(reason)}"}
    end
  end

  # defp execute_tool("create_task", params, user_id) do
  #   task_params = Map.put(params, "user_id", user_id)

  #   case FinancialAdvisorAi.AI.create_task(task_params) do
  #     {:ok, task} ->
  #       {:ok, %{tool: "create_task", task_id: task.id, status: "task_created"}}

  #     {:error, reason} ->
  #       {:error, "Failed to create task: #{inspect(reason)}"}
  #   end
  # end

  def execute_tool("find_calendar_availability", params, user_id) do
    # Ensure preferred_times is always a list, defaulting to empty list if nil
    preferred_times = params["preferred_times"] || []
    duration_minutes = params["duration_minutes"] || 60

    case CalendarService.find_free_time(
           user_id,
           duration_minutes,
           preferred_times
         ) do
      {:ok, availability} ->
        # Get user timezone for display purposes
        user = FinancialAdvisorAi.Accounts.get_user!(user_id)
        user_timezone = user.timezone || "UTC"

        # Format availability with timezone information
        formatted_availability =
          availability
          |> Enum.map(fn slot ->
            %{
              start_time: slot.start_time,
              end_time: slot.end_time,
              timezone: slot.timezone,
              duration_minutes: slot.duration_minutes
            }
          end)

        {:ok,
         %{
           tool: "find_calendar_availability",
           availability: formatted_availability,
           user_timezone: user_timezone,
           total_slots: length(availability)
         }}

      {:error, reason} ->
        {:error, "Failed to find calendar availability: #{inspect(reason)}"}
    end
  end

  def execute_tool(unknown_tool, _params, _user_id) do
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
        Enum.map_join(results, "\n", fn email ->
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

  defp format_success_result(%{
         tool: "create_contact",
         status: "contact_created",
         contact_id: contact_id
       }) do
    "✅ Contact created successfully! Contact ID: #{contact_id}"
  end

  defp format_success_result(%{
         tool: "create_contact",
         status: "contact_already_exists",
         contact_id: contact_id
       }) do
    "✅ Contact already exists in HubSpot! Contact ID: #{contact_id}"
  end

  defp format_success_result(%{tool: "create_contact", task_id: task_id}) do
    "✅ Created contact creation task (ID: #{task_id}). I'll add them to your CRM."
  end

  defp format_success_result(%{tool: "create_task", task_id: task_id}) do
    "✅ Created task (ID: #{task_id}) for follow-up."
  end

  defp format_success_result(%{
         tool: "find_calendar_availability",
         availability: availability,
         user_timezone: user_timezone,
         total_slots: total_slots
       }) do
    if total_slots > 0 do
      formatted_availability =
        Enum.map_join(availability, "\n", fn slot ->
          "• #{slot.start_time} - #{slot.end_time} (#{slot.timezone})"
        end)

      "✅ Found #{total_slots} available time slots in #{user_timezone}:\n#{formatted_availability}"
    else
      "❌ No available time slots found for your meeting. Please try a different duration or preferred times."
    end
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

  defp extract_existing_contact_id_from_message(message) when is_binary(message) do
    case Regex.run(~r/Existing ID: (\d+)/, message) do
      [_, contact_id] -> contact_id
      _ -> nil
    end
  end

  defp extract_existing_contact_id_from_message(_), do: nil
end

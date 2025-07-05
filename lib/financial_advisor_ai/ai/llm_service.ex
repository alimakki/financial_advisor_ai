defmodule FinancialAdvisorAi.AI.LlmService do
  @moduledoc """
  LLM service for generating AI responses using OpenAI API.
  Handles chat completions, tool calling, and context management.
  """

  require Logger

  @openai_api_url "https://api.openai.com/v1"
  @default_model "gpt-4o-mini"

  @doc """
  Generates an AI response based on user question and RAG context.
  """
  def generate_response(user_question, rag_context, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)

    system_prompt = build_system_prompt()
    user_prompt = build_user_prompt(user_question, rag_context)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]

    case make_openai_request(messages, model) do
      {:ok, response} ->
        content = get_in(response, ["choices", Access.at(0), "message", "content"])
        {:ok, content || "I apologize, but I couldn't generate a response at this time."}

      {:error, reason} ->
        Logger.warning("OpenAI API error: #{inspect(reason)}")
        {:ok, fallback_response(user_question, rag_context)}
    end
  end

  @doc """
  Generates a response with tool calling capabilities for task execution.
  """
  def generate_response_with_tools(user_question, rag_context, available_tools \\ []) do
    model = @default_model

    system_prompt = build_system_prompt_with_tools()
    user_prompt = build_user_prompt(user_question, rag_context)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]

    tools = build_tool_definitions(available_tools)

    case make_openai_request_with_tools(messages, model, tools) do
      {:ok, response} ->
        parse_tool_response(response)

      {:error, reason} ->
        Logger.warning("OpenAI API with tools error: #{inspect(reason)}")
        {:ok, fallback_response(user_question, rag_context)}
    end
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

    When a user requests an action that requires tool usage, use the appropriate tools to complete the task.
    Always explain what you're doing and ask for confirmation before taking significant actions.
    """
  end

  defp build_user_prompt(user_question, rag_context) do
    context_section =
      case {rag_context.emails, rag_context.contacts} do
        {[], []} ->
          "No relevant emails or contacts found for this query."

        {emails, contacts} ->
          email_context =
            if length(emails) > 0 do
              email_summaries =
                Enum.map(emails, fn email ->
                  "- From: #{email.sender}\n  Subject: #{email.subject}\n  Preview: #{email.content_preview}"
                end)
                |> Enum.join("\n")

              "Relevant Emails:\n#{email_summaries}"
            else
              ""
            end

          contact_context =
            if length(contacts) > 0 do
              contact_summaries =
                Enum.map(contacts, fn contact ->
                  "- #{contact.name} (#{contact.email}): #{contact.message_count} messages"
                end)
                |> Enum.join("\n")

              "\nRelevant Contacts:\n#{contact_summaries}"
            else
              ""
            end

          email_context <> contact_context
      end

    """
    User Question: #{user_question}

    Available Context:
    #{context_section}

    Please provide a helpful response based on the available context. If you need additional information
    to fully answer the question, suggest specific next steps.
    """
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

      case Req.post("#{@openai_api_url}/chat/completions", headers: headers, json: body) do
        {:ok, %{status: 200, body: response}} -> {:ok, response}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp make_openai_request_with_tools(messages, model, tools) do
    # For now, return a simple response - tool calling will be implemented later
    make_openai_request(messages, model)
  end

  defp build_tool_definitions(_available_tools) do
    # Tool definitions will be implemented when we add specific tools
    []
  end

  defp parse_tool_response(response) do
    # Tool response parsing will be implemented later
    content = get_in(response, ["choices", Access.at(0), "message", "content"])
    {:ok, content || "I apologize, but I couldn't generate a response at this time."}
  end

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
end

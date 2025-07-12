defmodule FinancialAdvisorAi.AI.RuleDetector do
  @moduledoc """
  Service for detecting and parsing automation rules from user messages using LLM.
  """

  require Logger
  alias FinancialAdvisorAi.AI.LlmService

  @max_retries 2
  @retry_delay_ms 1000

  @doc """
  Analyzes a message to determine if it contains an automation rule.
  Returns {:ok, rule_data} if it's a rule, {:ok, nil} if it's not a rule.
  """
  def analyze_message(message) do
    analyze_message_with_retry(message, @max_retries)
  end

  defp analyze_message_with_retry(message, retries_left) do
    messages = [
      %{
        role: "system",
        content: build_rule_detection_prompt()
      },
      %{role: "user", content: message}
    ]

    case LlmService.make_openai_request(messages, "gpt-4o-mini", %{temperature: 0.3}) do
      {:ok, %{"choices" => [%{"message" => %{"content" => response}}]}} ->
        parse_llm_response(response)

      {:error, %Req.TransportError{reason: :timeout}} when retries_left > 0 ->
        Logger.warning("Rule detection timeout, retrying... (#{retries_left} retries left)")
        Process.sleep(@retry_delay_ms)
        analyze_message_with_retry(message, retries_left - 1)

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.error("Rule detection timeout after all retries")
        {:error, :user_retry_needed}

      {:error, {status, _body}} when status >= 500 and retries_left > 0 ->
        Logger.warning(
          "Rule detection server error (#{status}), retrying... (#{retries_left} retries left)"
        )

        Process.sleep(@retry_delay_ms)
        analyze_message_with_retry(message, retries_left - 1)

      {:error, {status, body}} ->
        Logger.error("Rule detection API error: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("Rule detection LLM error: #{inspect(reason)}")
        {:error, :llm_error}
    end
  end

  defp build_rule_detection_prompt() do
    tool_descriptions =
      LlmService.tool_descriptions()
      |> Enum.map_join("|", fn %{name: name} -> name end)

    """
    You are an expert at detecting automation rules and instructions in user messages.

    Analyze the following message and determine if it contains an automation rule or instruction that should be executed automatically when certain conditions are met.

    Guidelines:
    - A rule is something that should happen automatically when certain conditions are met
    - Questions about existing data (like "when are my meetings?") are NOT rules
    - Instructions for one-time actions (like "send this email") are NOT rules
    - Ongoing instructions (like "when someone emails me...") ARE rules
    - Instructions with conditional logic (like "if X then Y") ARE rules

    Respond with ONLY a JSON object in this exact format:
    {
      "is_rule": true/false,
      "rule_data": {
        "trigger": "email_received|calendar_event_created|contact_created|note_created",
        "condition": {
          "description": "human readable condition",
          "parameters": {}
        },
        "actions": [
          {
            "type": "#{tool_descriptions}",
            "description": "human readable action",
            "parameters": {}
          }
        ]
      }
    }

    Examples:
    - "When someone emails me who is not in HubSpot, create a contact" -> is_rule: true
    - "When are my meetings tomorrow?" -> is_rule: false
    - "Always respond to emails about investments within 1 hour" -> is_rule: true
    - "Send John an email about the meeting" -> is_rule: false
    - "If someone mentions baseball, remind me to ask about their kids" -> is_rule: true

    Remember: Only respond with the JSON object, no other text.
    """
  end

  defp parse_llm_response(response) do
    case Jason.decode(response) do
      {:ok, %{"is_rule" => false}} ->
        {:ok, nil}

      {:ok, %{"is_rule" => true, "rule_data" => rule_data}} ->
        {:ok, normalize_rule_data(rule_data)}

      {:ok, %{"is_rule" => true}} ->
        Logger.warning("Rule detected but no rule_data provided")
        {:error, :invalid_rule_data}

      {:error, _} ->
        # Try to extract JSON from the response in case the LLM added extra text
        case extract_json_from_response(response) do
          {:ok, json} ->
            parse_llm_response(json)

          {:error, _} ->
            Logger.warning("Failed to parse rule detection response: #{response}")
            {:error, :invalid_json}
        end
    end
  end

  defp extract_json_from_response(response) do
    # Try to find JSON block in the response
    case Regex.run(~r/\{.*\}/s, response) do
      [json_str] -> {:ok, json_str}
      _ -> {:error, :no_json_found}
    end
  end

  defp normalize_rule_data(rule_data) do
    %{
      trigger: Map.get(rule_data, "trigger", "general"),
      condition: Map.get(rule_data, "condition", %{}),
      actions: normalize_actions(Map.get(rule_data, "actions", []))
    }
  end

  defp normalize_actions(actions) when is_list(actions) do
    Enum.map(actions, fn action ->
      %{
        "type" => Map.get(action, "type", "custom"),
        "description" => Map.get(action, "description", ""),
        "parameters" => Map.get(action, "parameters", %{})
      }
    end)
  end

  defp normalize_actions(_), do: []
end

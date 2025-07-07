defmodule FinancialAdvisorAi.AI.Agent do
  @moduledoc """
  AI Agent GenServer that manages a single user's AI assistant.

  Features:
  - Persistent agent per user (one agent per user across all sessions)
  - Task execution and monitoring
  - Memory of ongoing instructions
  - Proactive behavior based on events
  - Tool calling capabilities
  """

  use GenServer
  require Logger

  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.AI.{LlmService, RagService, AgentTools}

  # Agent state structure
  defstruct [
    :user_id,
    :status,
    :current_task,
    :memory,
    :ongoing_instructions,
    :last_activity,
    :task_queue,
    :event_queue
  ]

  # Client API

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via_tuple(user_id))
  end

  def get_or_start_agent(user_id) do
    case GenServer.whereis(via_tuple(user_id)) do
      nil ->
        case DynamicSupervisor.start_child(
               FinancialAdvisorAi.AI.AgentSupervisor,
               {__MODULE__, user_id}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end

      pid ->
        {:ok, pid}
    end
  end

  def process_message(user_id, message_content, conversation_id) do
    Logger.info(
      "Processing message for user #{user_id}: #{String.slice(message_content, 0, 50)}..."
    )

    {:ok, _pid} = get_or_start_agent(user_id)

    GenServer.call(
      via_tuple(user_id),
      {:process_message, message_content, conversation_id},
      60_000
    )
  end

  def handle_event(user_id, event_type, event_data) do
    Logger.info("Handling event for user #{user_id}: #{event_type}")

    {:ok, _pid} = get_or_start_agent(user_id)
    GenServer.cast(via_tuple(user_id), {:handle_event, event_type, event_data})
  end

  def add_ongoing_instruction(user_id, instruction) do
    Logger.info("Adding ongoing instruction for user #{user_id}: #{instruction}")

    {:ok, _pid} = get_or_start_agent(user_id)
    GenServer.call(via_tuple(user_id), {:add_ongoing_instruction, instruction}, 60_000)
  end

  def get_agent_status(user_id) do
    Logger.info("Getting agent status for user #{user_id}")

    case GenServer.whereis(via_tuple(user_id)) do
      nil -> {:error, :not_running}
      _pid -> GenServer.call(via_tuple(user_id), :get_status, 60_000)
    end
  end

  def stop_agent(user_id) do
    Logger.info("Stopping agent for user #{user_id}")

    case GenServer.whereis(via_tuple(user_id)) do
      nil -> :ok
      _pid -> GenServer.stop(via_tuple(user_id))
    end
  end

  # GenServer callbacks

  @impl GenServer
  def init(user_id) do
    Logger.info("Starting AI Agent for user #{user_id}")

    # Load existing ongoing instructions from database
    ongoing_instructions = AI.list_active_instructions(user_id)

    # Load pending tasks
    pending_tasks = AI.list_pending_tasks(user_id)

    state = %__MODULE__{
      user_id: user_id,
      status: :active,
      current_task: nil,
      memory: %{},
      ongoing_instructions: ongoing_instructions,
      last_activity: DateTime.utc_now(),
      task_queue: pending_tasks,
      event_queue: []
    }

    # Schedule periodic task processing
    schedule_task_processing()

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:process_message, message_content, _conversation_id}, _from, state) do
    Logger.info(
      "Agent processing message for user #{state.user_id}: #{String.slice(message_content, 0, 50)}..."
    )

    # Update last activity
    state = %{state | last_activity: DateTime.utc_now()}

    # Check if this is an ongoing instruction
    if contains_instruction_keywords?(message_content) do
      # Extract and store the instruction
      instruction = extract_instruction(message_content)

      {:ok, _} =
        AI.create_instruction(%{
          user_id: state.user_id,
          instruction: instruction,
          trigger_events: determine_trigger_events(instruction)
        })

      # Update state with new instruction
      instructions = AI.list_active_instructions(state.user_id)
      state = %{state | ongoing_instructions: instructions}

      response = "I've added that as an ongoing instruction. I'll remember to: #{instruction}"
      {:reply, {:ok, response}, state}
    else
      # Process as regular message with RAG and tool calling
      case process_user_message(message_content, state) do
        {:ok, response, new_state} ->
          {:reply, {:ok, response}, new_state}

        {:error, error} ->
          {:reply, {:error, error}, state}
      end
    end
  end

  @impl GenServer
  def handle_call({:add_ongoing_instruction, instruction}, _from, state) do
    case AI.create_instruction(%{
           user_id: state.user_id,
           instruction: instruction,
           trigger_events: determine_trigger_events(instruction)
         }) do
      {:ok, _} ->
        instructions = AI.list_active_instructions(state.user_id)
        state = %{state | ongoing_instructions: instructions}
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      user_id: state.user_id,
      status: state.status,
      current_task: state.current_task,
      pending_tasks: length(state.task_queue),
      ongoing_instructions: length(state.ongoing_instructions),
      last_activity: state.last_activity
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_cast({:handle_event, event_type, event_data}, state) do
    Logger.info("Agent handling #{event_type} event for user #{state.user_id}")

    # Add event to queue for processing
    event = %{
      type: event_type,
      data: event_data,
      timestamp: DateTime.utc_now()
    }

    state = %{state | event_queue: [event | state.event_queue]}

    # Process event immediately if relevant to ongoing instructions
    new_state = process_event_with_instructions(event, state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:process_tasks, state) do
    # Process pending tasks
    new_state = process_pending_tasks(state)

    # Process events
    new_state = process_pending_events(new_state)

    # Schedule next processing
    schedule_task_processing()

    {:noreply, new_state}
  end

  # Private functions

  defp via_tuple(user_id) do
    {:via, Registry, {FinancialAdvisorAi.AI.AgentRegistry, user_id}}
  end

  defp schedule_task_processing do
    # Every 30 seconds
    Process.send_after(self(), :process_tasks, 30_000)
  end

  defp process_user_message(message_content, state) do
    # Use RAG to get context
    context = RagService.search_by_question_type(state.user_id, message_content)

    # Add agent memory to context
    enhanced_context = add_agent_memory(context, state)

    # Check if this needs tool calling
    if contains_action_keywords?(message_content) do
      case LlmService.generate_response_with_tools(
             message_content,
             enhanced_context,
             state.user_id
           ) do
        {:ok, response} ->
          # Update agent memory with conversation
          memory = update_memory(state.memory, message_content, response)
          new_state = %{state | memory: memory}

          {:ok, response, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    else
      case LlmService.generate_response(message_content, enhanced_context) do
        {:ok, response} ->
          # Update agent memory
          memory = update_memory(state.memory, message_content, response)
          new_state = %{state | memory: memory}

          {:ok, response, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp process_pending_tasks(state) do
    case state.task_queue do
      [] ->
        state

      [task | remaining_tasks] ->
        Logger.info("Processing task #{task.id} for user #{state.user_id}")

        case execute_task(task, state) do
          {:ok, result} ->
            # Mark task as completed
            AI.update_task(task, %{
              status: "completed",
              result: result,
              completed_at: DateTime.utc_now()
            })

            %{state | task_queue: remaining_tasks, current_task: nil}

          {:error, reason} ->
            # Mark task as failed
            AI.update_task(task, %{
              status: "failed",
              error_message: inspect(reason)
            })

            %{state | task_queue: remaining_tasks, current_task: nil}

          {:retry, _reason} ->
            # Put task back at end of queue
            %{state | task_queue: remaining_tasks ++ [task], current_task: nil}
        end
    end
  end

  defp process_pending_events(state) do
    case state.event_queue do
      [] ->
        state

      events ->
        # Process all events
        Enum.each(events, fn event ->
          handle_proactive_event(event, state)
        end)

        # Clear event queue
        %{state | event_queue: []}
    end
  end

  defp process_event_with_instructions(event, state) do
    relevant_instructions = find_relevant_instructions(event, state.ongoing_instructions)

    if length(relevant_instructions) > 0 do
      # Create proactive tasks based on instructions
      tasks = create_proactive_tasks(event, relevant_instructions, state.user_id)

      # Add tasks to queue
      %{state | task_queue: state.task_queue ++ tasks}
    else
      state
    end
  end

  defp execute_task(task, state) do
    case task.task_type do
      "email" ->
        AgentTools.execute_email_task(task.parameters, state.user_id)

      "calendar" ->
        AgentTools.execute_calendar_task(task.parameters, state.user_id)

      "hubspot" ->
        AgentTools.execute_hubspot_task(task.parameters, state.user_id)

      "follow_up" ->
        AgentTools.execute_follow_up_task(task.parameters, state.user_id)

      _ ->
        {:error, "Unknown task type: #{task.task_type}"}
    end
  end

  defp handle_proactive_event(event, state) do
    # Check if this event should trigger proactive behavior
    case should_be_proactive?(event, state) do
      true ->
        Logger.info("Agent being proactive for #{event.type} event")
        # Generate proactive response using LLM
        generate_proactive_response(event, state)

      false ->
        :ok
    end
  end

  defp should_be_proactive?(event, state) do
    # Check if any ongoing instructions apply to this event
    relevant_instructions = find_relevant_instructions(event, state.ongoing_instructions)
    length(relevant_instructions) > 0
  end

  defp generate_proactive_response(event, state) do
    # Use LLM to determine what action to take
    context = %{
      event: event,
      ongoing_instructions: state.ongoing_instructions,
      user_id: state.user_id
    }

    prompt = build_proactive_prompt(context)

    case LlmService.generate_response_with_tools(
           prompt,
           %{emails: [], contacts: []},
           state.user_id
         ) do
      {:ok, response} ->
        Logger.info("Proactive response generated: #{String.slice(response, 0, 100)}...")

        # Optionally send notification to user about proactive action
        broadcast_proactive_action(state.user_id, response)

      {:error, reason} ->
        Logger.warning("Failed to generate proactive response: #{inspect(reason)}")
    end
  end

  defp broadcast_proactive_action(user_id, action) do
    Phoenix.PubSub.broadcast(
      FinancialAdvisorAi.PubSub,
      "agent:#{user_id}",
      {:proactive_action, action}
    )
  end

  defp contains_instruction_keywords?(message) do
    keywords = ["when", "always", "remember to", "ongoing", "instruction", "rule"]
    message_lower = String.downcase(message)
    Enum.any?(keywords, &String.contains?(message_lower, &1))
  end

  defp extract_instruction(message) do
    # Simple extraction - could be enhanced with NLP
    String.trim(message)
  end

  defp determine_trigger_events(instruction) do
    instruction_lower = String.downcase(instruction)

    events = []

    events =
      if String.contains?(instruction_lower, ["email", "message"]),
        do: ["gmail" | events],
        else: events

    events =
      if String.contains?(instruction_lower, ["calendar", "meeting", "appointment"]),
        do: ["calendar" | events],
        else: events

    events =
      if String.contains?(instruction_lower, ["contact", "hubspot", "crm"]),
        do: ["hubspot" | events],
        else: events

    if events == [], do: ["gmail", "calendar", "hubspot"], else: events
  end

  defp find_relevant_instructions(event, instructions) do
    Enum.filter(instructions, fn instruction ->
      event.type in instruction.trigger_events
    end)
  end

  defp create_proactive_tasks(event, instructions, user_id) do
    Enum.map(instructions, fn instruction ->
      # Create task based on instruction and event
      %{
        user_id: user_id,
        title: "Proactive: #{instruction.instruction}",
        description: "Auto-generated task based on #{event.type} event",
        task_type: "follow_up",
        parameters: %{
          event: event,
          instruction: instruction
        },
        scheduled_for: DateTime.utc_now()
      }
    end)
    |> Enum.map(fn task_attrs ->
      case AI.create_task(task_attrs) do
        {:ok, task} -> task
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp contains_action_keywords?(message) do
    keywords = [
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

    message_lower = String.downcase(message)
    Enum.any?(keywords, &String.contains?(message_lower, &1))
  end

  defp add_agent_memory(context, state) do
    # Add recent conversation memory to context
    Map.put(context, :agent_memory, state.memory)
  end

  defp update_memory(memory, user_message, agent_response) do
    # Keep last 10 exchanges in memory
    exchanges = Map.get(memory, :exchanges, [])

    new_exchange = %{
      user: user_message,
      agent: agent_response,
      timestamp: DateTime.utc_now()
    }

    updated_exchanges = [new_exchange | exchanges] |> Enum.take(10)
    Map.put(memory, :exchanges, updated_exchanges)
  end

  defp build_proactive_prompt(context) do
    """
    You are an AI Financial Advisor agent that is being proactive. A new event has occurred:

    Event Type: #{context.event.type}
    Event Data: #{inspect(context.event.data)}

    Your ongoing instructions are:
    #{Enum.map_join(context.ongoing_instructions, "\n", fn i -> "- #{i.instruction}" end)}

    Based on this event and your ongoing instructions, should you take any proactive action?
    If yes, describe what action you should take and use the appropriate tools.
    If no, respond with "No action needed."
    """
  end
end

defmodule FinancialAdvisorAi.AI.AgentSupervisor do
  @moduledoc """
  Dynamic supervisor for AI Agent processes.
  Manages one agent per user, ensuring agents are properly supervised.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_agent(user_id) do
    child_spec = %{
      id: user_id,
      start: {FinancialAdvisorAi.AI.Agent, :start_link, [user_id]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_agent(user_id) do
    case Registry.lookup(FinancialAdvisorAi.AI.AgentRegistry, user_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        :ok
    end
  end

  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
  end

  def agent_count do
    DynamicSupervisor.count_children(__MODULE__)
  end
end

defmodule FinancialAdvisorAi.AI.PollingWorkerTest do
  use ExUnit.Case, async: true

  alias FinancialAdvisorAi.AI.PollingWorker

  test "starts and schedules polling" do
    {:ok, pid} = PollingWorker.start_link([])
    assert Process.alive?(pid)
  end

  # More detailed integration tests would require mocking Accounts.list_users and the integration pollers
end

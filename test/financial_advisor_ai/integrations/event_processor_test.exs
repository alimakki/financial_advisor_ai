defmodule FinancialAdvisorAi.Integrations.EventProcessorTest do
  use ExUnit.Case, async: true

  alias FinancialAdvisorAi.Integrations.EventProcessor

  describe "process_webhook/3" do
    test "returns :not_implemented for known providers" do
      assert {:ok, :not_implemented} = EventProcessor.process_webhook("gmail", %{}, [])
      assert {:ok, :not_implemented} = EventProcessor.process_webhook("calendar", %{}, [])
      assert {:ok, :not_implemented} = EventProcessor.process_webhook("hubspot", %{}, [])
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = EventProcessor.process_webhook("unknown", %{}, [])
    end
  end

  describe "process_event/2" do
    test "returns :not_implemented for known providers" do
      assert {:ok, :not_implemented} = EventProcessor.process_event("gmail", %{})
      assert {:ok, :not_implemented} = EventProcessor.process_event("calendar", %{})
      assert {:ok, :not_implemented} = EventProcessor.process_event("hubspot", %{})
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = EventProcessor.process_event("unknown", %{})
    end
  end
end

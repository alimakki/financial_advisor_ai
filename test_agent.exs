#!/usr/bin/env elixir

# AI Agent System Demo Script
# This script demonstrates the AI agent capabilities

Mix.install([
  {:financial_advisor_ai, path: "."}
])

# Start the application
Application.ensure_all_started(:financial_advisor_ai)

# Demo user ID
user_id = 1

IO.puts("🤖 AI Financial Advisor Agent Demo")
IO.puts("==================================")
IO.puts("")

# 1. Start an agent for the user
IO.puts("1. Starting AI Agent for user #{user_id}...")
{:ok, agent_pid} = FinancialAdvisorAi.AI.Agent.get_or_start_agent(user_id)
IO.puts("   ✅ Agent started (PID: #{inspect(agent_pid)})")
IO.puts("")

# 2. Check agent status
IO.puts("2. Checking agent status...")
status = FinancialAdvisorAi.AI.Agent.get_agent_status(user_id)
IO.puts("   📊 Status: #{inspect(status)}")
IO.puts("")

# 3. Add ongoing instructions
IO.puts("3. Adding ongoing instructions...")

instructions = [
  "When someone emails me that is not in HubSpot, please create a contact in HubSpot with a note about the email",
  "When I create a contact in HubSpot, send them an email telling them thank you for being a client",
  "When I add an event in my calendar, send an email to attendees telling them about the meeting"
]

Enum.each(instructions, fn instruction ->
  :ok = FinancialAdvisorAi.AI.Agent.add_ongoing_instruction(user_id, instruction)
  IO.puts("   ✅ Added: #{String.slice(instruction, 0, 50)}...")
end)

IO.puts("")

# 4. Process chat messages
IO.puts("4. Processing chat messages...")

messages = [
  "Who mentioned their kid plays baseball?",
  "Schedule an appointment with Sara Smith tomorrow at 2 PM",
  "Send an email to john@example.com thanking him for the meeting",
  "Create a contact for Jane Doe (jane@example.com) - new client from referral"
]

Enum.each(messages, fn message ->
  IO.puts("   💬 User: #{message}")

  case FinancialAdvisorAi.AI.Agent.process_message(user_id, message, 1) do
    {:ok, response} ->
      IO.puts("   🤖 Agent: #{String.slice(response, 0, 100)}...")

    {:error, reason} ->
      IO.puts("   ❌ Error: #{inspect(reason)}")
  end

  IO.puts("")
  # Small delay to see the processing
  :timer.sleep(1000)
end)

# 5. Simulate events
IO.puts("5. Simulating incoming events...")

# Simulate Gmail event
gmail_event = %{
  "id" => "email_123",
  "from" => "newclient@example.com",
  "subject" => "Interested in financial planning",
  "body" => "Hi, I'm interested in your financial planning services. Can we schedule a meeting?",
  "timestamp" => DateTime.utc_now()
}

IO.puts("   📧 Processing Gmail event from newclient@example.com...")
FinancialAdvisorAi.AI.Agent.handle_event(user_id, "gmail", gmail_event)

# Simulate Calendar event
calendar_event = %{
  "id" => "event_456",
  "summary" => "Client Meeting - Financial Planning",
  "start_time" => "2024-01-15T14:00:00Z",
  "end_time" => "2024-01-15T15:00:00Z",
  "attendees" => [%{"email" => "client@example.com"}]
}

IO.puts("   📅 Processing Calendar event - Client Meeting...")
FinancialAdvisorAi.AI.Agent.handle_event(user_id, "calendar", calendar_event)

# Simulate HubSpot event
hubspot_event = %{
  "id" => "contact_789",
  "action" => "contact_created",
  "email" => "newclient@example.com",
  "firstname" => "John",
  "lastname" => "Smith"
}

IO.puts("   🔗 Processing HubSpot event - New contact created...")
FinancialAdvisorAi.AI.Agent.handle_event(user_id, "hubspot", hubspot_event)

IO.puts("")

# 6. Check agent status after processing
IO.puts("6. Final agent status...")
final_status = FinancialAdvisorAi.AI.Agent.get_agent_status(user_id)
IO.puts("   📊 Final Status: #{inspect(final_status)}")
IO.puts("")

# 7. List tasks
IO.puts("7. Checking agent tasks...")
tasks = FinancialAdvisorAi.AI.list_tasks(user_id)
IO.puts("   📋 Total tasks: #{length(tasks)}")

Enum.each(tasks, fn task ->
  IO.puts("   - [#{task.status}] #{task.title}")
end)

IO.puts("")

IO.puts("🎉 Demo completed!")
IO.puts("")
IO.puts("Key Features Demonstrated:")
IO.puts("✅ Agent lifecycle management (start/stop)")
IO.puts("✅ Ongoing instruction management")
IO.puts("✅ Chat message processing with tool calling")
IO.puts("✅ Event-driven proactive behavior")
IO.puts("✅ Task creation and management")
IO.puts("✅ Integration with Gmail, Calendar, and HubSpot")
IO.puts("")
IO.puts("Usage Examples:")
IO.puts("================")
IO.puts("")
IO.puts("Chat Examples:")
IO.puts('- "Schedule a meeting with John Smith"')
IO.puts('- "Send an email to jane@example.com about our services"')
IO.puts('- "Create a contact for Bob Johnson - new client"')
IO.puts('- "Who mentioned stocks in recent emails?"')
IO.puts("")
IO.puts("Ongoing Instructions:")
IO.puts('- "When someone emails me, always check if they are in HubSpot"')
IO.puts('- "When I schedule a meeting, send a confirmation email"')
IO.puts('- "Always follow up on tasks within 24 hours"')
IO.puts("")
IO.puts("Integration Features:")
IO.puts("📧 Gmail: Automatic email processing and responses")
IO.puts("📅 Calendar: Meeting scheduling and notifications")
IO.puts("🔗 HubSpot: Contact management and CRM updates")
IO.puts("🤖 AI: Smart task execution and proactive behavior")

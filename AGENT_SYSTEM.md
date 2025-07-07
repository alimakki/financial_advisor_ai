# AI Agent System for Financial Advisors

## Overview

The AI Agent System is a comprehensive, proactive AI assistant designed specifically for financial advisors. It integrates with Gmail, Google Calendar, and HubSpot to provide intelligent automation and assistance.

## Key Features

### 🤖 **Persistent Agent per User**
- One unique agent instance per logged-in user
- Agents persist across multiple browser sessions
- Automatic startup and shutdown management
- Memory retention between sessions

### 🧠 **Intelligent Task Management**
- Automatic task creation from user requests
- Background task execution
- Retry logic for failed tasks
- Task prioritization and scheduling

### 📝 **Ongoing Instructions & Memory**
- Users can set ongoing instructions that the agent remembers
- Proactive behavior based on events and instructions
- Contextual memory of recent conversations
- Smart trigger detection for different event types

### 🔧 **Comprehensive Tool System**
- Email sending and management
- Calendar scheduling and management
- HubSpot contact creation and updates
- Task creation and follow-up automation

### ⚡ **Event-Driven Proactivity**
- Reacts to incoming Gmail messages
- Responds to calendar events
- Handles HubSpot updates
- Automatic webhook processing

## Architecture

### Core Components

1. **Agent (`FinancialAdvisorAi.AI.Agent`)**
   - GenServer managing agent state
   - Handles message processing and tool calling
   - Manages memory and ongoing instructions

2. **Agent Supervisor (`FinancialAdvisorAi.AI.AgentSupervisor`)**
   - DynamicSupervisor for agent processes
   - Ensures one agent per user
   - Handles agent lifecycle

3. **Agent Tools (`FinancialAdvisorAi.AI.AgentTools`)**
   - Implements actual tool execution
   - Handles email, calendar, and HubSpot operations
   - Provides feedback and error handling

4. **Event Processor (`FinancialAdvisorAi.Integrations.EventProcessor`)**
   - Processes webhooks and polling events
   - Routes events to appropriate user agents
   - Handles event deduplication

## Usage Examples

### Basic Chat Interactions

```elixir
# User asks a question
user_message = "Who mentioned their kid plays baseball?"
{:ok, response} = FinancialAdvisorAi.AI.Agent.process_message(user_id, user_message, conversation_id)
```

### Action Requests

```elixir
# User requests an action
user_message = "Schedule an appointment with Sara Smith tomorrow at 2 PM"
{:ok, response} = FinancialAdvisorAi.AI.Agent.process_message(user_id, user_message, conversation_id)
# Agent creates calendar task and responds with confirmation
```

### Setting Ongoing Instructions

```elixir
# Add ongoing instruction
instruction = "When someone emails me that is not in HubSpot, please create a contact in HubSpot"
:ok = FinancialAdvisorAi.AI.Agent.add_ongoing_instruction(user_id, instruction)
```

### Proactive Event Handling

```elixir
# When a new email arrives, the agent automatically processes it
email_event = %{
  "from" => "newclient@example.com",
  "subject" => "Interested in financial planning",
  "body" => "Hi, I'd like to discuss my investments..."
}

# Agent checks ongoing instructions and may:
# 1. Create HubSpot contact if sender not found
# 2. Draft reply email
# 3. Schedule follow-up task
FinancialAdvisorAi.AI.Agent.handle_event(user_id, "gmail", email_event)
```

## Integration with ChatLive

The agent system is fully integrated with the ChatLive module:

```elixir
# In ChatLive, messages are processed by the agent
def handle_info({:process_llm_response, content, user_id, conversation_id}, socket) do
  ai_response = case FinancialAdvisorAi.AI.Agent.process_message(user_id, content, conversation_id) do
    {:ok, response} -> response
    {:error, reason} -> fallback_response(content)
  end
  
  # Create and broadcast message...
end
```

## Configuration

### Environment Variables

```bash
# OpenAI API Configuration
OPENAI_API_KEY=your_openai_api_key
OPENAI_BASE_URL=https://api.openai.com/v1

# Google OAuth
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# HubSpot OAuth
HUBSPOT_CLIENT_ID=your_hubspot_client_id
HUBSPOT_CLIENT_SECRET=your_hubspot_client_secret
```

### Database Setup

The system requires the following database tables:
- `conversations` - Chat conversations
- `messages` - Individual chat messages
- `tasks` - Agent tasks
- `ongoing_instructions` - User instructions
- `integrations` - OAuth integrations
- `email_embeddings` - RAG data storage

## API Reference

### Agent Management

```elixir
# Start or get existing agent
{:ok, pid} = FinancialAdvisorAi.AI.Agent.get_or_start_agent(user_id)

# Check agent status
status = FinancialAdvisorAi.AI.Agent.get_agent_status(user_id)

# Stop agent
:ok = FinancialAdvisorAi.AI.Agent.stop_agent(user_id)
```

### Message Processing

```elixir
# Process user message
{:ok, response} = FinancialAdvisorAi.AI.Agent.process_message(user_id, message, conversation_id)
```

### Instruction Management

```elixir
# Add ongoing instruction
:ok = FinancialAdvisorAi.AI.Agent.add_ongoing_instruction(user_id, instruction)

# List active instructions
instructions = FinancialAdvisorAi.AI.list_active_instructions(user_id)
```

### Event Handling

```elixir
# Handle external event
FinancialAdvisorAi.AI.Agent.handle_event(user_id, event_type, event_data)

# Process user-specific event
FinancialAdvisorAi.Integrations.EventProcessor.process_user_event(user_id, provider, event)
```

### Task Management

```elixir
# List user tasks
tasks = FinancialAdvisorAi.AI.list_tasks(user_id)

# List pending tasks
pending = FinancialAdvisorAi.AI.list_pending_tasks(user_id)

# Update task status
FinancialAdvisorAi.AI.update_task(task, %{status: "completed"})
```

## Advanced Features

### Custom Tool Development

You can extend the agent's capabilities by adding new tools to `AgentTools`:

```elixir
def execute_custom_task(parameters, user_id) do
  # Your custom tool implementation
  case perform_custom_action(parameters) do
    {:ok, result} -> {:ok, %{type: "custom_action", result: result}}
    {:error, reason} -> {:retry, reason}
  end
end
```

### Webhook Integration

Set up webhooks for real-time event processing:

```elixir
# Gmail webhook endpoint
post "/webhooks/gmail", WebhookController, :gmail_webhook

# Calendar webhook endpoint  
post "/webhooks/calendar", WebhookController, :calendar_webhook

# HubSpot webhook endpoint
post "/webhooks/hubspot", WebhookController, :hubspot_webhook
```

### Memory and Context Management

The agent maintains conversation memory and context:

```elixir
# Agent automatically maintains:
# - Last 10 conversation exchanges
# - Active ongoing instructions
# - Task queue and status
# - Event processing history
```

## Example Scenarios

### Scenario 1: New Client Email
1. Client emails financial advisor
2. Agent detects new email via webhook/polling
3. Agent checks if sender exists in HubSpot
4. If not found, creates new HubSpot contact
5. Agent drafts appropriate response email
6. Creates follow-up task for advisor

### Scenario 2: Meeting Scheduling
1. User says "Schedule meeting with John Smith"
2. Agent searches for John's contact info
3. Agent checks calendar availability
4. Agent creates calendar event
5. Agent sends meeting confirmation email
6. Agent adds note to HubSpot contact

### Scenario 3: Proactive Follow-up
1. User sets instruction: "Follow up on all new contacts within 24 hours"
2. New HubSpot contact is created
3. Agent automatically creates follow-up task
4. After 24 hours, agent reminds user to follow up

## Troubleshooting

### Common Issues

1. **Agent not starting**: Check database connection and migrations
2. **No responses**: Verify OpenAI API key and configuration
3. **Integration failures**: Check OAuth tokens and refresh logic
4. **Memory issues**: Monitor agent process memory usage

### Debugging

```elixir
# Enable debug logging
config :logger, level: :debug

# Check agent status
FinancialAdvisorAi.AI.Agent.get_agent_status(user_id)

# List running agents
FinancialAdvisorAi.AI.AgentSupervisor.list_agents()
```

## Security Considerations

- OAuth tokens are encrypted in database
- Agent processes are isolated per user
- Webhook endpoints should verify signatures
- Rate limiting on API calls
- User data access controls

## Performance

- Agents are lightweight GenServer processes
- Task processing is asynchronous
- Event deduplication prevents duplicate processing
- Periodic cleanup of old data
- Connection pooling for external APIs

## Contributing

To extend the agent system:

1. Add new tools to `AgentTools`
2. Extend event processing in `EventProcessor`
3. Add new instruction patterns
4. Implement additional integrations
5. Enhance memory and context management

## Testing

Run the demo script to see the agent in action:

```bash
elixir test_agent.exs
```

This demonstrates all major features including:
- Agent startup and management
- Instruction handling
- Message processing
- Event simulation
- Task management 
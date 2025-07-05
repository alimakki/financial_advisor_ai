# AI Financial Advisor Agent - Implementation Plan

## Overview
Building a sophisticated AI agent for Financial Advisors with Gmail, Google Calendar, and HubSpot integrations, featuring a ChatGPT-like interface with RAG capabilities.

## Detailed Steps:

### Phase 1: Authentication & Setup (Steps 2-4)
- [x] Generate Phoenix app with SQLite
- [x] Add required dependencies (OAuth, HTTP clients, AI/ML libraries)
- [x] Set up Google OAuth (Gmail + Calendar permissions)
- [ ] Set up HubSpot OAuth integration

### Phase 2: Database & Core Models (Steps 5-6)
- [x] Create user authentication with Google OAuth
- [x] Create core schemas:
  - Users, conversations, messages, tasks
  - Ongoing instructions, integrations
  - Email/contact embeddings for RAG

### Phase 3: Integration Services (Steps 7-10)
- [ ] Gmail Service (read/write emails, webhook handling)
- [ ] Google Calendar Service (read/write events)
- [ ] HubSpot Service (contacts, notes, CRM operations)
- [ ] RAG Service (embedding generation, vector search)

### Phase 4: Chat Interface (Steps 11-13)
- [x] Replace home page with professional modern design mockup
- [ ] Create ChatLive with real-time messaging
- [ ] Style interface to match provided design (clean whites/grays)

### Phase 5: AI Agent Core (Steps 14-17)
- [ ] LLM integration with tool calling (OpenAI/Anthropic)
- [ ] Task management system with persistence
- [ ] Proactive monitoring system for webhooks
- [ ] Ongoing instructions management

### Phase 6: Integration & Testing (Step 18)
- [ ] Wire all systems together
- [ ] Test core scenarios (scheduling, contact management, email responses)

## Key Features to Implement:
- Google OAuth with Gmail/Calendar permissions + webshookeng@gmail.com as test user
- HubSpot CRM integration via OAuth
- RAG system for contextual question answering
- Flexible tool calling for task execution
- Persistent task memory across sessions
- Proactive webhook monitoring
- Professional chat interface matching design

## Technical Stack:
- Phoenix LiveView for real-time UI
- SQLite with vector embeddings (will upgrade to pgvector later)
- Google APIs (Gmail, Calendar)
- HubSpot API
- OpenAI/Anthropic for LLM + tool calling
- Tailwind CSS for professional styling


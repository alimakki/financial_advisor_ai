defmodule FinancialAdvisorAi.AI do
  @moduledoc """
  The AI context for managing conversations, messages, tasks, and integrations.
  """

  import Ecto.Query, warn: false
  alias FinancialAdvisorAi.Repo

  alias FinancialAdvisorAi.AI.{
    Conversation,
    Message,
    Task,
    OngoingInstruction,
    Integration,
    EmailEmbedding
  }

  # Conversations

  def list_conversations(user_id) do
    Conversation
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  def get_conversation!(id), do: Repo.get!(Conversation, id)

  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  # Messages

  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def create_message(attrs \\ %{}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  # Tasks

  def list_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def list_pending_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id and t.status == "pending")
    |> order_by([t], asc: :scheduled_for)
    |> Repo.all()
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  # Ongoing Instructions

  def list_active_instructions(user_id) do
    OngoingInstruction
    |> where([i], i.user_id == ^user_id and i.is_active == true)
    |> order_by([i], desc: :priority)
    |> Repo.all()
  end

  def create_instruction(attrs \\ %{}) do
    %OngoingInstruction{}
    |> OngoingInstruction.changeset(attrs)
    |> Repo.insert()
  end

  # Integrations

  def get_integration(user_id, provider) do
    Integration
    |> where([i], i.user_id == ^user_id and i.provider == ^provider)
    |> Repo.one()
  end

  def upsert_integration(attrs) do
    case get_integration(attrs.user_id, attrs.provider) do
      nil ->
        %Integration{}
        |> Integration.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Integration.changeset(attrs)
        |> Repo.update()
    end
  end

  # Email Embeddings

  def create_email_embedding(attrs \\ %{}) do
    %EmailEmbedding{}
    |> EmailEmbedding.changeset(attrs)
    |> Repo.insert()
  end

  def search_emails_by_content(user_id, query) do
    # This will be enhanced with vector search later
    EmailEmbedding
    |> where([e], e.user_id == ^user_id)
    |> where([e], ilike(e.content, ^"%#{query}%") or ilike(e.subject, ^"%#{query}%"))
    |> Repo.all()
  end
end

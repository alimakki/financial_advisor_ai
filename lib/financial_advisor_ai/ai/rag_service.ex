defmodule FinancialAdvisorAi.AI.RagService do
  @moduledoc """
  RAG (Retrieval-Augmented Generation) service for searching through emails,
  contacts, and other data to provide context for AI responses.
  """

  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.AI.{EmailEmbedding, ContactEmbedding, ContactNote, LlmService}
  alias FinancialAdvisorAi.Repo
  import Ecto.Query
  import Pgvector.Ecto.Query

  @doc """
  Searches emails and contacts based on a text query using vector similarity.
  Returns relevant context that can be used by the LLM.
  """
  def search_context(user_id, query) do
    # Use vector search for better semantic matching
    email_results = search_emails_by_vector(user_id, query)
    hubspot_contact_results = search_hubspot_contacts_by_vector(user_id, query)
    contact_note_results = search_contact_notes_by_vector(user_id, query)
    email_contact_results = search_contacts_by_content(user_id, query)

    %{
      emails: email_results,
      contacts: email_contact_results,
      hubspot_contacts: hubspot_contact_results,
      contact_notes: contact_note_results,
      summary:
        generate_search_summary(
          email_results,
          email_contact_results,
          hubspot_contact_results,
          contact_note_results,
          query
        )
    }
  end

  @doc """
  Searches for contact notes using vector similarity (cosine distance).
  """
  def search_contact_notes_by_vector(user_id, query, limit \\ 10) do
    # Generate embedding for the query
    case LlmService.create_embedding(query) do
      {:ok, response} ->
        # Extract the embedding vector from the response
        query_embedding = get_in(response, ["data", Access.at(0), "embedding"])

        if query_embedding do
          # Use PostgreSQL's vector similarity search with cosine distance
          ContactNote
          |> where([n], n.user_id == ^user_id)
          |> where([n], not is_nil(n.embedding))
          |> where([n], cosine_distance(n.embedding, ^query_embedding) < 0.5)
          |> order_by([n], cosine_distance(n.embedding, ^query_embedding))
          |> limit(^limit)
          |> Repo.all()
          |> Enum.map(&format_contact_note_result/1)
        else
          # Fallback to text search if embedding creation fails
          search_contact_notes_by_content(user_id, query)
        end

      {:error, _} ->
        # Fallback to text search if embedding creation fails
        search_contact_notes_by_content(user_id, query)
    end
  end

  @doc """
  Searches for HubSpot contacts using vector similarity (cosine distance).
  """
  def search_hubspot_contacts_by_vector(user_id, query, limit \\ 10) do
    # Generate embedding for the query
    case LlmService.create_embedding(query) do
      {:ok, response} ->
        # Extract the embedding vector from the response
        query_embedding = get_in(response, ["data", Access.at(0), "embedding"])

        if query_embedding do
          # Use PostgreSQL's vector similarity search with cosine distance
          ContactEmbedding
          |> where([c], c.user_id == ^user_id)
          |> where([c], not is_nil(c.embedding))
          |> where([c], cosine_distance(c.embedding, ^query_embedding) < 0.5)
          |> order_by([c], cosine_distance(c.embedding, ^query_embedding))
          |> limit(^limit)
          |> Repo.all()
          |> Enum.map(&format_contact_result/1)
        else
          # Fallback to text search if embedding creation fails
          search_hubspot_contacts_by_content(user_id, query)
        end

      {:error, _} ->
        # Fallback to text search if embedding creation fails
        search_hubspot_contacts_by_content(user_id, query)
    end
  end

  @doc """
  Searches for emails using vector similarity (cosine distance).
  """
  def search_emails_by_vector(user_id, query, limit \\ 10) do
    # Generate embedding for the query
    case LlmService.create_embedding(query) do
      {:ok, response} ->
        # Extract the embedding vector from the response
        query_embedding = get_in(response, ["data", Access.at(0), "embedding"])

        if query_embedding do
          # Use PostgreSQL's vector similarity search with cosine distance
          EmailEmbedding
          |> where([e], e.user_id == ^user_id)
          |> where([e], not is_nil(e.embedding))
          |> where([e], cosine_distance(e.embedding, ^query_embedding) < 0.5)
          |> order_by([e], cosine_distance(e.embedding, ^query_embedding))
          |> limit(^limit)
          |> Repo.all()
          |> Enum.map(&format_email_result/1)
        else
          # Fallback to text search if embedding creation fails
          search_emails_by_content(user_id, query)
        end

      {:error, _} ->
        # Fallback to text search if embedding creation fails
        search_emails_by_content(user_id, query)
    end
  end

  @doc """
  Processes and stores contact content for RAG search.
  Includes embedding generation.
  """
  def process_contact_for_rag(user_id, contact_data) do
    # Extract key information from contact
    content = extract_contact_content(contact_data)

    # Generate embedding for the contact content
    embedding =
      case LlmService.create_embedding(content) do
        {:ok, response} ->
          get_in(response, ["data", Access.at(0), "embedding"])

        {:error, _} ->
          nil
      end

    contact_embedding_attrs = %{
      user_id: user_id,
      contact_id: contact_data["id"] || contact_data[:id],
      firstname: contact_data["firstname"] || contact_data[:firstname],
      lastname: contact_data["lastname"] || contact_data[:lastname],
      email: contact_data["email"] || contact_data[:email],
      company: contact_data["company"] || contact_data[:company],
      phone: contact_data["phone"] || contact_data[:phone],
      lifecycle_stage: contact_data["lifecycle_stage"] || contact_data[:lifecycle_stage],
      lead_status: contact_data["lead_status"] || contact_data[:lead_status],
      notes: contact_data["notes"] || contact_data[:notes],
      content: content,
      embedding: embedding,
      metadata: %{
        created_at: contact_data["created_at"] || contact_data[:created_at],
        updated_at: contact_data["updated_at"] || contact_data[:updated_at],
        processed_at: DateTime.utc_now(),
        importance: calculate_contact_importance(contact_data, content)
      }
    }

    AI.create_contact_embedding(contact_embedding_attrs)
  end

  @doc """
  Processes and stores email content for RAG search.
  Now includes embedding generation.
  """
  def process_email_for_rag(user_id, email_data) do
    # Extract key information from email
    content = extract_email_content(email_data)
    keywords = extract_keywords(content)

    # Generate embedding for the email content
    embedding =
      case LlmService.create_embedding(content) do
        {:ok, response} ->
          get_in(response, ["data", Access.at(0), "embedding"])

        {:error, _} ->
          nil
      end

    embedding_attrs = %{
      user_id: user_id,
      email_id: email_data["id"] || generate_email_id(),
      subject: email_data["subject"] || "",
      content: content,
      sender: email_data["from"] || email_data["sender"] || "",
      recipient: email_data["to"] || email_data["recipient"] || "",
      embedding: embedding,
      metadata: %{
        keywords: keywords,
        thread_id: email_data["thread_id"],
        labels: email_data["labels"] || [],
        date: email_data["date"],
        importance: calculate_importance(email_data, content)
      }
    }

    AI.create_email_embedding(embedding_attrs)
  end

  @doc """
  Searches for relevant information based on specific question types.
  Now uses vector search for better semantic matching.
  """
  def search_by_question_type(user_id, question) do
    search_context(user_id, question)
  end

  # Private functions

  defp search_emails_by_content(user_id, query) do
    query_terms = String.split(query, " ") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    EmailEmbedding
    |> where([e], e.user_id == ^user_id)
    |> where(
      [e],
      fragment("? LIKE ? OR ? LIKE ?", e.content, ^"%#{query}%", e.subject, ^"%#{query}%")
    )
    |> where([e], fragment("? LIKE ?", e.content, ^"%#{Enum.join(query_terms, "%")}%"))
    |> order_by([e], desc: e.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(&format_email_result/1)
  end

  defp search_contacts_by_content(user_id, query) do
    # This will search through email senders/recipients as a proxy for contacts
    EmailEmbedding
    |> where([e], e.user_id == ^user_id)
    |> where(
      [e],
      fragment("? LIKE ? OR ? LIKE ?", e.sender, ^"%#{query}%", e.recipient, ^"%#{query}%")
    )
    |> group_by([e], e.sender)
    |> select([e], %{
      name: e.sender,
      email: e.sender,
      last_contact: max(e.inserted_at),
      message_count: count(e.id)
    })
    |> limit(5)
    |> Repo.all()
  end

  defp extract_email_content(email_data) do
    content = email_data["content"] || email_data["body"] || ""
    subject = email_data["subject"] || ""
    "#{subject} #{content}"
  end

  defp extract_keywords(content) do
    # Simple keyword extraction - can be enhanced with NLP libraries
    content
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.take(20)
  end

  defp calculate_importance(_email_data, content) do
    # Simple importance scoring based on content length and keywords
    base_score = String.length(content) / 100
    keyword_bonus = if String.contains?(content, ["urgent", "important", "asap"]), do: 2, else: 0
    min(base_score + keyword_bonus, 10)
  end

  defp generate_email_id do
    "email_#{System.unique_integer([:positive])}"
  end

  defp format_email_result(email_embedding) do
    %{
      id: email_embedding.email_id,
      subject: email_embedding.subject,
      sender: email_embedding.sender,
      content_preview: String.slice(email_embedding.content, 0, 200),
      date: email_embedding.inserted_at,
      relevance_score: email_embedding.metadata["importance"] || 1
    }
  end

  defp generate_search_summary(
         email_results,
         contact_results,
         hubspot_contact_results,
         contact_note_results,
         query
       ) do
    email_count = length(email_results)
    contact_count = length(contact_results)
    hubspot_contact_count = length(hubspot_contact_results)
    contact_note_count = length(contact_note_results)

    "Found #{email_count} relevant emails, #{contact_count} email contacts, #{hubspot_contact_count} HubSpot contacts, and #{contact_note_count} contact notes for query: '#{query}'"
  end

  defp search_hubspot_contacts_by_content(user_id, query) do
    ContactEmbedding
    |> where([c], c.user_id == ^user_id)
    |> where(
      [c],
      fragment(
        "? LIKE ? OR ? LIKE ? OR ? LIKE ? OR ? LIKE ?",
        c.content,
        ^"%#{query}%",
        c.firstname,
        ^"%#{query}%",
        c.lastname,
        ^"%#{query}%",
        c.email,
        ^"%#{query}%"
      )
    )
    |> order_by([c], desc: c.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(&format_contact_result/1)
  end

  defp format_contact_result(contact_embedding) do
    full_name = "#{contact_embedding.firstname} #{contact_embedding.lastname}" |> String.trim()

    %{
      id: contact_embedding.contact_id,
      name: if(full_name == "", do: contact_embedding.email, else: full_name),
      email: contact_embedding.email,
      company: contact_embedding.company,
      phone: contact_embedding.phone,
      lifecycle_stage: contact_embedding.lifecycle_stage,
      content_preview: String.slice(contact_embedding.content, 0, 200),
      date: contact_embedding.inserted_at,
      relevance_score: Map.get(contact_embedding.metadata, "importance", 1)
    }
  end

  defp extract_contact_content(contact_data) do
    firstname = contact_data["firstname"] || contact_data[:firstname] || ""
    lastname = contact_data["lastname"] || contact_data[:lastname] || ""
    email = contact_data["email"] || contact_data[:email] || ""
    company = contact_data["company"] || contact_data[:company] || ""
    phone = contact_data["phone"] || contact_data[:phone] || ""
    lifecycle_stage = contact_data["lifecycle_stage"] || contact_data[:lifecycle_stage] || ""
    lead_status = contact_data["lead_status"] || contact_data[:lead_status] || ""
    notes = contact_data["notes"] || contact_data[:notes] || ""

    # Create structured content for embedding
    parts =
      [
        "Name: #{firstname} #{lastname}",
        "Email: #{email}",
        "Company: #{company}",
        "Phone: #{phone}",
        "Lifecycle Stage: #{lifecycle_stage}",
        "Lead Status: #{lead_status}",
        "Notes: #{notes}"
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(". ")

    if parts == "", do: "Contact record", else: parts
  end

  defp calculate_contact_importance(contact_data, content) do
    # Simple importance scoring based on available data
    base_score = 1

    # Add score for having company info
    company_bonus =
      if (contact_data["company"] || contact_data[:company]) not in [nil, ""], do: 1, else: 0

    # Add score for having phone number
    phone_bonus =
      if (contact_data["phone"] || contact_data[:phone]) not in [nil, ""], do: 1, else: 0

    # Add score for having notes
    notes_bonus =
      if (contact_data["notes"] || contact_data[:notes]) not in [nil, ""], do: 2, else: 0

    # Add score for content length
    content_bonus = String.length(content) / 100

    min(base_score + company_bonus + phone_bonus + notes_bonus + content_bonus, 10)
  end

  defp search_contact_notes_by_content(user_id, query) do
    ContactNote
    |> where([n], n.user_id == ^user_id)
    |> where([n], ilike(n.content, ^"%#{query}%"))
    |> order_by([n], desc: n.inserted_at)
    |> limit(10)
    |> Repo.all()
    |> Enum.map(&format_contact_note_result/1)
  end

  defp format_contact_note_result(contact_note) do
    %{
      id: contact_note.id,
      hubspot_note_id: contact_note.hubspot_note_id,
      content_preview: String.slice(contact_note.content, 0, 200),
      content: contact_note.content,
      date: contact_note.inserted_at,
      relevance_score: 1,
      contact_embedding_id: contact_note.contact_embedding_id
    }
  end
end

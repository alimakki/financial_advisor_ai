defmodule FinancialAdvisorAi.AI.RagService do
  @moduledoc """
  RAG (Retrieval-Augmented Generation) service for searching through emails,
  contacts, and other data to provide context for AI responses.
  """

  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.AI.{EmailEmbedding, LlmService}
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
    contact_results = search_contacts_by_content(user_id, query)

    %{
      emails: email_results,
      contacts: contact_results,
      summary: generate_search_summary(email_results, contact_results, query)
    }
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
          |> order_by([e], fragment("? <=> ?", e.embedding, ^query_embedding))
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

  # @doc """
  # Searches for emails using vector similarity with a threshold.
  # Only returns emails with similarity above the threshold.
  # """
  # def search_emails_by_vector_with_threshold(user_id, query, threshold \\ 0.8, limit \\ 10) do
  #   case LlmService.create_embedding(query) do
  #     {:ok, response} ->
  #       query_embedding = get_in(response, ["data", Access.at(0), "embedding"])

  #       if query_embedding do
  #         # Use cosine distance with threshold
  #         EmailEmbedding
  #         |> where([e], e.user_id == ^user_id)
  #         |> where([e], not is_nil(e.embedding))
  #         |> where([e], fragment("1 - (? <=> ?) > ?", e.embedding, ^query_embedding, ^threshold))
  #         |> order_by([e], fragment("? <=> ?", e.embedding, ^query_embedding))
  #         |> limit(^limit)
  #         |> Repo.all()
  #         |> Enum.map(&format_email_result/1)
  #       else
  #         []
  #       end

  #     {:error, _} ->
  #       []
  #   end
  # end

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
    question_lower = String.downcase(question)

    cond do
      contains_family_keywords?(question_lower) ->
        search_family_mentions_vector(user_id, question)

      contains_stock_keywords?(question_lower) ->
        search_stock_mentions_vector(user_id, question)

      contains_meeting_keywords?(question_lower) ->
        search_meeting_mentions_vector(user_id, question)

      true ->
        search_context(user_id, question)
    end
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

  defp search_family_mentions_vector(user_id, query) do
    # Use vector search with family-related context
    family_query = "#{query} family children kids baseball soccer school activities"

    results = search_emails_by_vector(user_id, family_query, 15)

    %{
      emails: results,
      contacts: [],
      summary:
        "Found #{length(results)} emails mentioning family-related topics using semantic search"
    }
  end

  defp search_stock_mentions_vector(user_id, query) do
    # Use vector search with investment-related context
    stock_query = "#{query} stock investment portfolio market trading finance"

    results = search_emails_by_vector(user_id, stock_query, 10)

    %{
      emails: results,
      contacts: [],
      summary: "Found #{length(results)} emails about stocks or investments using semantic search"
    }
  end

  defp search_meeting_mentions_vector(user_id, query) do
    # Use vector search with meeting-related context
    meeting_query = "#{query} meeting appointment schedule calendar call conference"

    results = search_emails_by_vector(user_id, meeting_query, 10)

    %{
      emails: results,
      contacts: [],
      summary:
        "Found #{length(results)} emails about meetings or scheduling using semantic search"
    }
  end

  defp contains_family_keywords?(question) do
    family_keywords = [
      "kid",
      "child",
      "son",
      "daughter",
      "family",
      "baseball",
      "soccer",
      "school"
    ]

    Enum.any?(family_keywords, &String.contains?(question, &1))
  end

  defp contains_stock_keywords?(question) do
    stock_keywords = ["stock", "aapl", "investment", "portfolio", "sell", "buy"]
    Enum.any?(stock_keywords, &String.contains?(question, &1))
  end

  defp contains_meeting_keywords?(question) do
    meeting_keywords = ["meeting", "appointment", "schedule", "calendar"]
    Enum.any?(meeting_keywords, &String.contains?(question, &1))
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

  defp generate_search_summary(email_results, contact_results, query) do
    email_count = length(email_results)
    contact_count = length(contact_results)

    "Found #{email_count} relevant emails and #{contact_count} contacts for query: '#{query}'"
  end
end

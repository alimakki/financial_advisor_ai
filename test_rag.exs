alias FinancialAdvisorAi.{AI, Accounts, Repo}
alias FinancialAdvisorAi.AI.RagService

user = Repo.get_by!(Accounts.User, email: "webshookeng@gmail.com")
IO.puts("Testing RAG system for user: #{user.email}")

# Test basic email search
emails = AI.search_emails_by_content(user.id, "baseball")
IO.puts("Direct search found #{length(emails)} emails with 'baseball'")

# Test RAG service
context = RagService.search_by_question_type(user.id, "Who mentioned their kid plays baseball")
IO.puts("RAG service found #{length(context.emails)} emails")

Enum.each(context.emails, fn email ->
  IO.puts("- #{email.sender}: #{email.subject}")
end)

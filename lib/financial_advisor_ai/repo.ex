defmodule FinancialAdvisorAi.Repo do
  use Ecto.Repo,
    otp_app: :financial_advisor_ai,
    adapter: Ecto.Adapters.Postgres
end

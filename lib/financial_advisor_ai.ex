defmodule FinancialAdvisorAi do
  @moduledoc """
  FinancialAdvisorAi keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def db_schema do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
      @foreign_key_type :binary_id

      @timestamps_opts [type: :utc_datetime_usec]
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

==> unzip
Compiling 6 files (.ex)
Generated unzip app
==> progress_bar
Compiling 10 files (.ex)
Generated progress_bar app
==> financial_advisor_ai
===> Analyzing applications...
===> Compiling unicode_util_compat
===> Analyzing applications...
===> Compiling idna
==> poison
Compiling 4 files (.ex)
Compiling lib/poison/parser.ex (it's taking more than 10s)
Generated poison app
==> financial_advisor_ai
===> Analyzing applications...
===> Compiling mimerl
==> unpickler
Compiling 3 files (.ex)
Generated unpickler app
==> ssl_verify_fun
Compiling 7 files (.erl)
Generated ssl_verify_fun app
==> complex
Compiling 2 files (.ex)
Generated complex app
==> nx
Compiling 36 files (.ex)
Generated nx app
==> nx_image
Compiling 1 file (.ex)
Generated nx_image app
==> nx_signal
Compiling 5 files (.ex)
Generated nx_signal app
==> safetensors
Compiling 3 files (.ex)
Generated safetensors app
==> polaris
Compiling 5 files (.ex)
Generated polaris app
==> axon
Compiling 27 files (.ex)
Generated axon app
==> financial_advisor_ai
===> Analyzing applications...
===> Compiling certifi
==> ueberauth
Compiling 9 files (.ex)
Generated ueberauth app
==> financial_advisor_ai
===> Analyzing applications...
===> Compiling parse_trans
===> Analyzing applications...
===> Compiling metrics
===> Analyzing applications...
===> Compiling hackney
==> castore
Compiling 1 file (.ex)
Generated castore app
==> mint
Compiling 1 file (.erl)
Compiling 20 files (.ex)
Generated mint app
==> finch
Compiling 14 files (.ex)
Generated finch app
==> tesla
Compiling 40 files (.ex)
Generated tesla app
==> oauth2
Compiling 13 files (.ex)
Generated oauth2 app
==> ueberauth_google
Compiling 3 files (.ex)
Generated ueberauth_google app
==> req
Compiling 18 files (.ex)
Generated req app
==> rustler_precompiled
Compiling 4 files (.ex)
Generated rustler_precompiled app
==> tokenizers
Compiling 18 files (.ex)

13:24:28.858 [debug] Downloading NIF from https://github.com/elixir-nx/tokenizers/releases/download/v0.5.1/libex_tokenizers-v0.5.1-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz

13:24:29.462 [debug] NIF cached at /root/.cache/rustler_precompiled/precompiled_nifs/libex_tokenizers-v0.5.1-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz and extracted to /workspace/financial_advisor_ai/_build/dev/lib/tokenizers/priv/native/libex_tokenizers-v0.5.1-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz
Generated tokenizers app
==> bumblebee
Compiling 95 files (.ex)
Generated bumblebee app
==> swoosh
Compiling 53 files (.ex)
Generated swoosh app
defmodule FinancialAdvisorAi.MixProject do
  use Mix.Project

  def project do
    [
      app: :financial_advisor_ai,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {FinancialAdvisorAi.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bandit, "~> 1.5"},
      # OAuth and integrations
      {:ueberauth, "~> 0.10"},
      {:ueberauth_google, "~> 0.12"},
      # Vector embeddings and AI
      {:nx, "~> 0.7"},
      {:bumblebee, "~> 0.5"},
      # HTTP clients
      {:tesla, "~> 1.8"},
      {:hackney, "~> 1.20"},
      # JSON handling
      {:poison, "~> 5.0"},
      {:phoenix, "~> 1.8.0-rc.3", override: true},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.9"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind financial_advisor_ai", "esbuild financial_advisor_ai"],
      "assets.deploy": [
        "tailwind financial_advisor_ai --minify",
        "esbuild financial_advisor_ai --minify",
        "phx.digest"
      ]
    ]
  end
end

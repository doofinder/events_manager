defmodule EventsManager.MixProject do
  use Mix.Project

  @source_url "https://github.com/doofinder/events_manager"
  @version "2.0.2"

  def project do
    [
      aliases: aliases(),
      app: :events_manager,
      version: @version,
      elixir: "~> 1.9",
      elixirc_paths: elixir_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description:
        "Events manager is an application to manage events sent by RabbitMQ using AMQP protocol",
      package: package(),

      # Docs
      docs: docs(),

      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  defp package do
    [
      organization: "doofinder",
      licenses: [],
      links: %{"GitHub" => @source_url}
    ]

  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:lager, :logger],
      mod: {EventsManager.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 2.0"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:earmark_parser, "<= 1.4.10", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.22.0", only: :dev, runtime: false},
      {:jason, "~> 1.2"}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixir_paths(:test), do: ["lib", "test/support"]
  defp elixir_paths(_), do: ["lib"]

  defp aliases do
    [
      consistency: [
        "format",
        "coveralls",
        "dialyzer --ignore-exit-status",
        "credo --strict"
      ]
    ]
  end
end

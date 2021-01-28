defmodule EventsManager.MixProject do
  use Mix.Project

  @version "1.0.0"

  def project do
    [
      app: :events_manager,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        extras: ["README.md"],
        main: "readme",
        source_ref: "v#{@version}",
        source_url: "https://github.com/doofinder/events_manager"
      ],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EventsManager.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 1.6"},
      {:ex_doc, "~> 0.22.0", only: :dev, runtime: false}
    ]
  end
end

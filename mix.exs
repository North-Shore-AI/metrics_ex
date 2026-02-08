defmodule MetricsEx.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/North-Shore-AI/metrics_ex"

  def version, do: @version

  def project do
    [
      app: :metrics_ex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "MetricsEx",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MetricsEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Metrics aggregation service for experiment results and system health monitoring.
    """
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/metrics_ex.svg",
      extras: [
        "README.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          MetricsEx,
          MetricsEx.Metric,
          MetricsEx.Recorder,
          MetricsEx.Aggregator
        ],
        Storage: [
          MetricsEx.Storage.ETS,
          MetricsEx.Storage.Prometheus
        ],
        Exporters: [
          MetricsEx.Exporters.OpenTelemetry,
          MetricsEx.Exporters.Datadog,
          MetricsEx.Exporters.InfluxDB
        ],
        Utilities: [
          MetricsEx.Alerting,
          MetricsEx.TelemetryHandler,
          MetricsEx.Tagging,
          MetricsEx.Aggregations,
          MetricsEx.API
        ]
      ]
    ]
  end

  defp package do
    [
      name: "metrics_ex",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE assets)
    ]
  end
end

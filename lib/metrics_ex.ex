defmodule MetricsEx do
  @moduledoc """
  MetricsEx - Centralized metrics aggregation service.

  Provides comprehensive metrics collection, aggregation, and querying for:
  - Experiment results (Crucible)
  - Model performance (CNS agents)
  - System health (Work jobs, services)
  - Training progress (Tinkex)

  ## Features

  - **Multiple metric types**: counters, gauges, histograms
  - **Fast in-memory storage**: ETS-based with configurable retention
  - **Flexible aggregations**: mean, sum, count, percentiles, time series
  - **Telemetry integration**: Auto-attach to telemetry events
  - **Export formats**: JSON API, Prometheus text format
  - **Real-time streaming**: Phoenix PubSub integration

  ## Quick Start

      # Record metrics
      MetricsEx.record(:experiment_result, %{
        experiment_id: "exp_123",
        metric: :entailment_score,
        value: 0.75,
        tags: %{model: "llama-3.1", dataset: "scifact"}
      })

      MetricsEx.increment(:jobs_completed, tags: %{tenant: "cns"})
      MetricsEx.gauge(:queue_depth, 42, tags: %{queue: "sno_validation"})

      # Query and aggregate
      MetricsEx.query(:experiment_result,
        metric: :entailment_score,
        group_by: [:model],
        aggregation: :mean,
        window: :last_24h
      )

      # Attach to telemetry
      MetricsEx.attach_telemetry([
        {[:work, :job, :completed], :counter},
        {[:crucible, :experiment, :completed], :histogram}
      ])
  """

  alias MetricsEx.{Recorder, Aggregator, TelemetryHandler, API}

  # Recorder delegations

  @doc """
  Records a generic metric.

  ## Examples

      iex> MetricsEx.record(:experiment_result, %{
      ...>   value: 0.75,
      ...>   tags: %{model: "llama-3.1"}
      ...> })
      :ok
  """
  defdelegate record(name, data), to: Recorder

  @doc """
  Increments a counter metric.

  ## Examples

      iex> MetricsEx.increment(:requests_total)
      :ok

      iex> MetricsEx.increment(:requests_total, 5, tags: %{endpoint: "/api"})
      :ok
  """
  defdelegate increment(name, amount \\ 1, opts \\ []), to: Recorder

  @doc """
  Records a gauge metric (point-in-time value).

  ## Examples

      iex> MetricsEx.gauge(:queue_depth, 42, tags: %{queue: "default"})
      :ok
  """
  defdelegate gauge(name, value, opts \\ []), to: Recorder

  @doc """
  Records a histogram metric (distribution of values).

  ## Examples

      iex> MetricsEx.histogram(:response_time, 123.45, tags: %{endpoint: "/api"})
      :ok
  """
  defdelegate histogram(name, value, opts \\ []), to: Recorder

  @doc """
  Measures execution time and records as histogram.

  ## Examples

      iex> MetricsEx.measure(:database_query, fn ->
      ...>   # expensive operation
      ...> end, tags: %{query: "SELECT"})
  """
  defdelegate measure(name, fun, opts \\ []), to: Recorder

  # Aggregator delegations

  @doc """
  Queries metrics with optional aggregation and grouping.

  ## Examples

      iex> MetricsEx.query(:jobs_completed,
      ...>   aggregation: :sum,
      ...>   group_by: [:tenant],
      ...>   window: :last_24h
      ...> )
      [%{tenant: "cns", sum: 1234}, ...]
  """
  defdelegate query(name, opts \\ []), to: Aggregator

  @doc """
  Returns time series data with fixed interval buckets.

  ## Examples

      iex> MetricsEx.time_series(:jobs_completed,
      ...>   interval: :hour,
      ...>   aggregation: :count,
      ...>   window: :last_24h
      ...> )
      [%{timestamp: ~U[...], count: 45}, ...]
  """
  defdelegate time_series(name, opts \\ []), to: Aggregator

  @doc """
  Calculates pre-aggregated rollups.

  ## Examples

      iex> MetricsEx.rollup(:experiment_result,
      ...>   group_by: [:model],
      ...>   aggregations: [:mean, :count],
      ...>   window: :last_24h
      ...> )
      %{"llama-3.1" => %{mean: 0.72, count: 150}, ...}
  """
  defdelegate rollup(name, opts \\ []), to: Aggregator

  # Telemetry delegations

  @doc """
  Attaches MetricsEx to telemetry events.

  ## Examples

      iex> MetricsEx.attach_telemetry([
      ...>   {[:work, :job, :completed], :counter},
      ...>   {[:work, :job, :duration], :histogram}
      ...> ])
      :ok
  """
  defdelegate attach_telemetry(event_configs, opts \\ []), to: TelemetryHandler

  @doc """
  Detaches MetricsEx from telemetry events.
  """
  defdelegate detach_telemetry(handler_id \\ :metrics_ex_telemetry_handler), to: TelemetryHandler

  # API delegations

  @doc """
  Returns metrics in JSON-compatible format.
  """
  defdelegate get_metrics(opts \\ []), to: API

  @doc """
  Returns aggregated metrics in JSON format.
  """
  defdelegate get_aggregation(name, opts \\ []), to: API

  @doc """
  Returns time series in JSON format.
  """
  defdelegate get_time_series(name, opts \\ []), to: API

  @doc """
  Returns rollups in JSON format.
  """
  defdelegate get_rollups(name, opts \\ []), to: API

  @doc """
  Returns system statistics.
  """
  defdelegate get_stats(), to: API

  @doc """
  Encodes data to JSON string.
  """
  defdelegate to_json(data), to: API
end

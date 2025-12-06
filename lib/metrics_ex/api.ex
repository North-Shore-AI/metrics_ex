defmodule MetricsEx.API do
  @moduledoc """
  JSON API for dashboard consumption and metric queries.

  Provides a simple interface for retrieving and aggregating metrics
  in JSON format suitable for web dashboards and external tools.
  """

  alias MetricsEx.{Aggregator, Storage.ETS, Metric}

  @doc """
  Returns metrics in JSON-compatible format.

  ## Options
    - `:name` - Filter by metric name
    - `:type` - Filter by metric type
    - `:tags` - Filter by tags
    - `:since` - Only return metrics after this DateTime
    - `:until` - Only return metrics before this DateTime
    - `:limit` - Maximum number of results

  ## Examples

      iex> MetricsEx.API.get_metrics(name: :jobs_completed, limit: 10)
      %{
        metrics: [
          %{name: :jobs_completed, type: :counter, value: 1, tags: %{tenant: "cns"}, ...},
          ...
        ],
        count: 10
      }
  """
  def get_metrics(opts \\ []) do
    metrics = ETS.query(opts)

    %{
      metrics: Enum.map(metrics, &Metric.to_map/1),
      count: length(metrics),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Returns aggregated metrics grouped by specified fields.

  ## Examples

      iex> MetricsEx.API.get_aggregation(
      ...>   :experiment_result,
      ...>   group_by: [:model],
      ...>   aggregation: :mean,
      ...>   window: :last_24h
      ...> )
      %{
        results: [
          %{model: "llama-3.1", mean: 0.72},
          %{model: "qwen", mean: 0.68}
        ],
        aggregation: :mean,
        window: :last_24h,
        timestamp: "2025-12-06T12:00:00Z"
      }
  """
  def get_aggregation(name, opts \\ []) do
    window = Keyword.get(opts, :window)
    time_range = if window, do: window_to_time_range(window), else: Keyword.get(opts, :time_range)

    query_opts =
      opts
      |> Keyword.put(:time_range, time_range)
      |> Keyword.delete(:window)

    results = Aggregator.query(name, query_opts)

    %{
      results: results,
      aggregation: Keyword.get(opts, :aggregation),
      group_by: Keyword.get(opts, :group_by, []),
      window: window,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Returns time series data for a metric.

  ## Examples

      iex> MetricsEx.API.get_time_series(
      ...>   :jobs_completed,
      ...>   interval: :hour,
      ...>   aggregation: :count,
      ...>   window: :last_24h
      ...> )
      %{
        series: [
          %{timestamp: "2025-12-06T00:00:00Z", count: 45},
          %{timestamp: "2025-12-06T01:00:00Z", count: 52},
          ...
        ],
        interval: :hour,
        aggregation: :count,
        window: :last_24h
      }
  """
  def get_time_series(name, opts \\ []) do
    window = Keyword.get(opts, :window, :last_24h)
    time_range = window_to_time_range(window)

    query_opts =
      opts
      |> Keyword.put(:time_range, time_range)
      |> Keyword.delete(:window)

    series = Aggregator.time_series(name, query_opts)

    # Convert timestamps to ISO8601 strings
    series_with_string_timestamps =
      Enum.map(series, fn point ->
        Map.update!(point, :timestamp, &DateTime.to_iso8601/1)
      end)

    %{
      series: series_with_string_timestamps,
      interval: Keyword.get(opts, :interval, :hour),
      aggregation: Keyword.get(opts, :aggregation, :count),
      window: window,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Returns pre-computed rollups for common dashboard queries.

  ## Examples

      iex> MetricsEx.API.get_rollups(
      ...>   :experiment_result,
      ...>   group_by: [:model, :dataset],
      ...>   aggregations: [:mean, :count, :p95],
      ...>   window: :last_24h
      ...> )
      %{
        rollups: %{
          "llama-3.1/scifact" => %{mean: 0.72, count: 150, p95: 0.89},
          "qwen/fever" => %{mean: 0.68, count: 200, p95: 0.85}
        },
        window: :last_24h,
        timestamp: "2025-12-06T12:00:00Z"
      }
  """
  def get_rollups(name, opts \\ []) do
    rollups = Aggregator.rollup(name, opts)

    %{
      rollups: rollups,
      group_by: Keyword.get(opts, :group_by, []),
      aggregations: Keyword.get(opts, :aggregations, [:mean, :count]),
      window: Keyword.get(opts, :window, :last_24h),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Returns system statistics and health information.

  ## Examples

      iex> MetricsEx.API.get_stats()
      %{
        storage: %{
          total_metrics: 12345,
          memory_bytes: 1048576,
          ...
        },
        recorder: %{
          metrics_recorded: 12345
        },
        timestamp: "2025-12-06T12:00:00Z"
      }
  """
  def get_stats do
    storage_stats = ETS.stats()
    recorder_stats = GenServer.call(MetricsEx.Recorder, :stats)

    %{
      storage: storage_stats,
      recorder: recorder_stats,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  rescue
    _ ->
      %{
        error: "Failed to retrieve stats",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
  end

  @doc """
  Encodes data to JSON string.

  ## Examples

      iex> data = MetricsEx.API.get_metrics(limit: 5)
      iex> MetricsEx.API.to_json(data)
      "{\"metrics\":[...],\"count\":5,...}"
  """
  def to_json(data) do
    Jason.encode!(data)
  end

  # Private functions

  defp window_to_time_range(:last_hour) do
    now = DateTime.utc_now()
    {DateTime.add(now, -3600, :second), now}
  end

  defp window_to_time_range(:last_24h) do
    now = DateTime.utc_now()
    {DateTime.add(now, -86400, :second), now}
  end

  defp window_to_time_range(:last_7d) do
    now = DateTime.utc_now()
    {DateTime.add(now, -604_800, :second), now}
  end

  defp window_to_time_range(:last_30d) do
    now = DateTime.utc_now()
    {DateTime.add(now, -2_592_000, :second), now}
  end
end

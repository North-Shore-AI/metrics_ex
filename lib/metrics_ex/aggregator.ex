defmodule MetricsEx.Aggregator do
  @moduledoc """
  Provides aggregation and querying capabilities for metrics.

  Supports various aggregation functions:
  - `:mean` - Average value
  - `:sum` - Total sum
  - `:count` - Number of metrics
  - `:min` - Minimum value
  - `:max` - Maximum value
  - `:p50`, `:p95`, `:p99` - Percentiles
  """

  alias MetricsEx.Storage.ETS

  @type aggregation :: :mean | :sum | :count | :min | :max | :p50 | :p95 | :p99
  @type group_by :: [atom()]
  @type time_range :: {DateTime.t(), DateTime.t()}

  @doc """
  Queries metrics with optional aggregation and grouping.

  ## Examples

      # Get mean entailment score grouped by model
      iex> MetricsEx.Aggregator.query(:experiment_result,
      ...>   metric: :entailment_score,
      ...>   group_by: [:model],
      ...>   aggregation: :mean,
      ...>   time_range: {~U[2025-12-01 00:00:00Z], ~U[2025-12-06 23:59:59Z]}
      ...> )
      [
        %{model: "llama-3.1", mean: 0.72},
        %{model: "qwen", mean: 0.68}
      ]

      # Get total job count by tenant
      iex> MetricsEx.Aggregator.query(:jobs_completed,
      ...>   aggregation: :sum,
      ...>   group_by: [:tenant]
      ...> )
      [
        %{tenant: "cns", sum: 1234},
        %{tenant: "crucible", sum: 567}
      ]
  """
  def query(name, opts \\ []) do
    aggregation = Keyword.get(opts, :aggregation)
    group_by = Keyword.get(opts, :group_by, [])
    time_range = Keyword.get(opts, :time_range)
    tags_filter = Keyword.get(opts, :tags, %{})

    # Build query options for storage
    storage_opts = build_storage_opts(name, time_range, tags_filter)

    # Retrieve metrics from storage
    metrics = ETS.query(storage_opts)

    # Group and aggregate
    if Enum.empty?(group_by) do
      # No grouping - return single aggregated value
      if aggregation do
        aggregate_metrics(metrics, aggregation)
      else
        metrics
      end
    else
      # Group by specified fields
      metrics
      |> group_metrics(group_by)
      |> Enum.map(fn {group_key, group_metrics} ->
        result =
          if aggregation do
            Map.put(group_key, aggregation, aggregate_metrics(group_metrics, aggregation))
          else
            Map.put(group_key, :metrics, group_metrics)
          end

        result
      end)
    end
  end

  @doc """
  Calculates a time series with fixed interval buckets.

  ## Examples

      iex> MetricsEx.Aggregator.time_series(:jobs_completed,
      ...>   interval: :hour,
      ...>   aggregation: :count,
      ...>   time_range: {start_time, end_time}
      ...> )
      [
        %{timestamp: ~U[2025-12-06 00:00:00Z], count: 45},
        %{timestamp: ~U[2025-12-06 01:00:00Z], count: 52},
        ...
      ]
  """
  def time_series(name, opts \\ []) do
    interval = Keyword.get(opts, :interval, :hour)
    aggregation = Keyword.get(opts, :aggregation, :count)
    time_range = Keyword.get(opts, :time_range)
    tags_filter = Keyword.get(opts, :tags, %{})

    storage_opts = build_storage_opts(name, time_range, tags_filter)
    metrics = ETS.query(storage_opts)

    metrics
    |> group_by_time_bucket(interval)
    |> Enum.map(fn {bucket_time, bucket_metrics} ->
      value = aggregate_metrics(bucket_metrics, aggregation)
      Map.put(%{timestamp: bucket_time}, aggregation, value)
    end)
    |> Enum.sort_by(& &1.timestamp, DateTime)
  end

  @doc """
  Calculates rollups (pre-aggregated values) for common queries.

  Useful for dashboard performance.

  ## Examples

      iex> MetricsEx.Aggregator.rollup(:experiment_result,
      ...>   group_by: [:model, :dataset],
      ...>   aggregations: [:mean, :count, :p95],
      ...>   window: :last_24h
      ...> )
      %{
        "llama-3.1/scifact" => %{mean: 0.72, count: 150, p95: 0.89},
        "qwen/fever" => %{mean: 0.68, count: 200, p95: 0.85}
      }
  """
  def rollup(name, opts \\ []) do
    group_by = Keyword.get(opts, :group_by, [])
    aggregations = Keyword.get(opts, :aggregations, [:mean, :count])
    window = Keyword.get(opts, :window, :last_24h)
    tags_filter = Keyword.get(opts, :tags, %{})

    time_range = window_to_time_range(window)
    storage_opts = build_storage_opts(name, time_range, tags_filter)
    metrics = ETS.query(storage_opts)

    metrics
    |> group_metrics(group_by)
    |> Enum.into(%{}, fn {group_key, group_metrics} ->
      group_key_str = format_group_key(group_key)

      rollup_values =
        Enum.into(aggregations, %{}, fn agg ->
          {agg, aggregate_metrics(group_metrics, agg)}
        end)

      {group_key_str, rollup_values}
    end)
  end

  # Private functions

  defp build_storage_opts(name, time_range, tags_filter) do
    opts = [name: name, tags: tags_filter]

    case time_range do
      {since, until_time} ->
        opts ++ [since: since, until: until_time]

      nil ->
        opts
    end
  end

  defp group_metrics(metrics, group_by) do
    Enum.group_by(metrics, fn metric ->
      Enum.into(group_by, %{}, fn field ->
        {field, Map.get(metric.tags, field)}
      end)
    end)
  end

  defp aggregate_metrics(metrics, :count) do
    length(metrics)
  end

  defp aggregate_metrics(metrics, :sum) do
    metrics
    |> Enum.map(& &1.value)
    |> Enum.sum()
  end

  defp aggregate_metrics(metrics, :mean) do
    values = Enum.map(metrics, & &1.value)

    if Enum.empty?(values) do
      0.0
    else
      Enum.sum(values) / length(values)
    end
  end

  defp aggregate_metrics(metrics, :min) do
    metrics
    |> Enum.map(& &1.value)
    |> Enum.min(fn -> 0 end)
  end

  defp aggregate_metrics(metrics, :max) do
    metrics
    |> Enum.map(& &1.value)
    |> Enum.max(fn -> 0 end)
  end

  defp aggregate_metrics(metrics, percentile) when percentile in [:p50, :p95, :p99] do
    percentile_value =
      case percentile do
        :p50 -> 0.50
        :p95 -> 0.95
        :p99 -> 0.99
      end

    values = metrics |> Enum.map(& &1.value) |> Enum.sort()

    if Enum.empty?(values) do
      0.0
    else
      index = round(length(values) * percentile_value) - 1
      index = max(0, index)
      Enum.at(values, index)
    end
  end

  defp group_by_time_bucket(metrics, interval) do
    Enum.group_by(metrics, fn metric ->
      truncate_to_bucket(metric.timestamp, interval)
    end)
  end

  defp truncate_to_bucket(datetime, :minute) do
    %{datetime | second: 0, microsecond: {0, 6}}
  end

  defp truncate_to_bucket(datetime, :hour) do
    %{datetime | minute: 0, second: 0, microsecond: {0, 6}}
  end

  defp truncate_to_bucket(datetime, :day) do
    %{datetime | hour: 0, minute: 0, second: 0, microsecond: {0, 6}}
  end

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

  defp format_group_key(group_key) do
    group_key
    |> Enum.map(fn {_k, v} -> to_string(v) end)
    |> Enum.join("/")
  end
end

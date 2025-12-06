defmodule MetricsEx.Aggregations do
  @moduledoc """
  Advanced aggregation functions for metrics analysis.

  Provides enhanced statistical functions including:
  - Precise percentile calculations
  - Rate calculations (per second/minute)
  - Moving averages (EMA, SMA)
  - Histogram buckets
  """

  alias MetricsEx.Metric

  @doc """
  Calculates precise percentiles using linear interpolation.

  More accurate than simple rank-based percentiles for small datasets.

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.percentile(metrics, 0.95)
      85.5
  """
  @spec percentile(list(Metric.t()), float()) :: float()
  def percentile(metrics, percentile_value) when is_list(metrics) do
    values = metrics |> Enum.map(& &1.value) |> Enum.sort()

    if Enum.empty?(values) do
      0.0
    else
      percentile_from_sorted(values, percentile_value)
    end
  end

  @doc """
  Calculates multiple percentiles at once (more efficient).

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.percentiles(metrics, [0.50, 0.95, 0.99])
      %{p50: 50.0, p95: 85.5, p99: 95.2}
  """
  @spec percentiles(list(Metric.t()), list(float())) :: map()
  def percentiles(metrics, percentile_values) when is_list(metrics) do
    values = metrics |> Enum.map(& &1.value) |> Enum.sort()

    if Enum.empty?(values) do
      Enum.into(percentile_values, %{}, fn p ->
        {percentile_label(p), 0.0}
      end)
    else
      Enum.into(percentile_values, %{}, fn p ->
        {percentile_label(p), percentile_from_sorted(values, p)}
      end)
    end
  end

  @doc """
  Calculates rate of change per second.

  Requires metrics to have timestamps. Returns metrics per second.

  ## Examples

      iex> metrics = [...]  # Metrics over 60 seconds
      iex> MetricsEx.Aggregations.rate_per_second(metrics)
      42.5  # 42.5 events per second
  """
  @spec rate_per_second(list(Metric.t())) :: float()
  def rate_per_second(metrics) when is_list(metrics) do
    calculate_rate(metrics, 1)
  end

  @doc """
  Calculates rate of change per minute.

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.rate_per_minute(metrics)
      2550.0  # 2550 events per minute
  """
  @spec rate_per_minute(list(Metric.t())) :: float()
  def rate_per_minute(metrics) when is_list(metrics) do
    calculate_rate(metrics, 60)
  end

  @doc """
  Calculates Simple Moving Average (SMA) over a window.

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.sma(metrics, window: 10)
      [%{timestamp: ~U[...], value: 45.2}, ...]
  """
  @spec sma(list(Metric.t()), keyword()) :: list(map())
  def sma(metrics, opts \\ []) do
    window = Keyword.get(opts, :window, 10)

    metrics
    |> Enum.sort_by(& &1.timestamp, DateTime)
    |> Enum.chunk_every(window, 1, :discard)
    |> Enum.map(fn window_metrics ->
      avg_value =
        window_metrics |> Enum.map(& &1.value) |> Enum.sum() |> Kernel./(length(window_metrics))

      %{
        timestamp: List.last(window_metrics).timestamp,
        value: avg_value
      }
    end)
  end

  @doc """
  Calculates Exponential Moving Average (EMA).

  EMA gives more weight to recent values. Alpha parameter controls the decay rate.

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.ema(metrics, alpha: 0.1)
      [%{timestamp: ~U[...], value: 45.8}, ...]

  ## Options

    * `:alpha` - Smoothing factor (0 < alpha <= 1). Default: 0.1
      - Smaller alpha = more smoothing (slower response)
      - Larger alpha = less smoothing (faster response)
  """
  @spec ema(list(Metric.t()), keyword()) :: list(map())
  def ema(metrics, opts \\ []) do
    alpha = Keyword.get(opts, :alpha, 0.1)

    sorted_metrics = Enum.sort_by(metrics, & &1.timestamp, DateTime)

    case sorted_metrics do
      [] ->
        []

      [first | rest] ->
        {_, result} =
          Enum.reduce(
            rest,
            {first.value, [%{timestamp: first.timestamp, value: first.value}]},
            fn metric, {prev_ema, acc} ->
              new_ema = alpha * metric.value + (1 - alpha) * prev_ema
              {new_ema, acc ++ [%{timestamp: metric.timestamp, value: new_ema}]}
            end
          )

        result
    end
  end

  @doc """
  Creates histogram buckets with configurable boundaries.

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.histogram_buckets(metrics, boundaries: [0, 10, 50, 100, 500])
      %{
        "0-10" => 5,
        "10-50" => 15,
        "50-100" => 30,
        "100-500" => 20,
        "500+" => 10
      }
  """
  @spec histogram_buckets(list(Metric.t()), keyword()) :: map()
  def histogram_buckets(metrics, opts \\ []) do
    boundaries = Keyword.get(opts, :boundaries, default_boundaries())

    values = Enum.map(metrics, & &1.value)

    # Initialize all buckets to 0
    initialized_buckets =
      boundaries
      |> create_bucket_labels()
      |> Enum.into(%{}, fn label -> {label, 0} end)

    # Count values in each bucket
    Enum.reduce(values, initialized_buckets, fn value, acc ->
      bucket_label = find_bucket(value, boundaries)
      Map.update(acc, bucket_label, 1, &(&1 + 1))
    end)
  end

  @doc """
  Calculates standard deviation of metric values.

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.std_dev(metrics)
      12.5
  """
  @spec std_dev(list(Metric.t())) :: float()
  def std_dev(metrics) when is_list(metrics) do
    values = Enum.map(metrics, & &1.value)

    if Enum.empty?(values) do
      0.0
    else
      mean = Enum.sum(values) / length(values)

      variance =
        Enum.reduce(values, 0, fn x, acc -> acc + :math.pow(x - mean, 2) end) / length(values)

      :math.sqrt(variance)
    end
  end

  @doc """
  Calculates coefficient of variation (CV).

  CV = (standard deviation / mean) * 100

  Useful for comparing variability between datasets with different means.

  ## Examples

      iex> metrics = [...]
      iex> MetricsEx.Aggregations.coefficient_of_variation(metrics)
      25.5  # 25.5% variability
  """
  @spec coefficient_of_variation(list(Metric.t())) :: float()
  def coefficient_of_variation(metrics) when is_list(metrics) do
    values = Enum.map(metrics, & &1.value)

    if Enum.empty?(values) do
      0.0
    else
      mean = Enum.sum(values) / length(values)

      if mean == 0 do
        0.0
      else
        std = std_dev(metrics)
        std / mean * 100
      end
    end
  end

  # Private functions

  defp percentile_from_sorted(sorted_values, percentile_value) do
    n = length(sorted_values)
    rank = percentile_value * (n - 1)
    lower_index = floor(rank)
    upper_index = ceil(rank)

    if lower_index == upper_index do
      Enum.at(sorted_values, lower_index)
    else
      # Linear interpolation
      lower_value = Enum.at(sorted_values, lower_index)
      upper_value = Enum.at(sorted_values, upper_index)
      fraction = rank - lower_index
      lower_value + fraction * (upper_value - lower_value)
    end
  end

  defp percentile_label(value) do
    String.to_atom("p#{trunc(value * 100)}")
  end

  defp calculate_rate(metrics, time_unit_seconds) when is_list(metrics) do
    if Enum.empty?(metrics) or length(metrics) < 2 do
      0.0
    else
      sorted = Enum.sort_by(metrics, & &1.timestamp, DateTime)
      first = List.first(sorted)
      last = List.last(sorted)

      time_diff_seconds = DateTime.diff(last.timestamp, first.timestamp, :second)

      if time_diff_seconds == 0 do
        0.0
      else
        count = length(metrics)
        rate_per_second = count / time_diff_seconds
        rate_per_second * time_unit_seconds
      end
    end
  end

  defp default_boundaries do
    [0, 1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10_000]
  end

  defp create_bucket_labels(boundaries) do
    boundaries
    |> Enum.chunk_every(2, 1)
    |> Enum.map(fn
      [lower, upper] -> "#{lower}-#{upper}"
      [lower] -> "#{lower}+"
    end)
  end

  defp find_bucket(value, boundaries) do
    boundaries
    |> Enum.chunk_every(2, 1)
    |> Enum.find_value(fn
      [lower, upper] ->
        if value >= lower and value < upper, do: "#{lower}-#{upper}"

      [lower] ->
        if value >= lower, do: "#{lower}+"
    end) || "0-#{hd(boundaries)}"
  end
end

defmodule MetricsEx.Metric do
  @moduledoc """
  Defines metric types and structures for MetricsEx.

  Supports three primary metric types:
  - Counter: Monotonically increasing value (e.g., request count)
  - Gauge: Point-in-time value that can go up or down (e.g., queue depth)
  - Histogram: Distribution of values (e.g., response times)
  """

  @type metric_type :: :counter | :gauge | :histogram
  @type tags :: %{optional(atom()) => String.t() | atom()}

  @type t :: %__MODULE__{
          name: atom(),
          type: metric_type(),
          value: number() | [number()],
          tags: tags(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :name,
    :type,
    :value,
    tags: %{},
    timestamp: nil,
    metadata: %{}
  ]

  @doc """
  Creates a new counter metric.

  ## Examples

      iex> MetricsEx.Metric.counter(:jobs_completed, 5, %{tenant: "cns"})
      %MetricsEx.Metric{name: :jobs_completed, type: :counter, value: 5, tags: %{tenant: "cns"}}
  """
  @spec counter(atom(), number(), tags(), map()) :: t()
  def counter(name, value \\ 1, tags \\ %{}, metadata \\ %{}) do
    %__MODULE__{
      name: name,
      type: :counter,
      value: value,
      tags: tags,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  @doc """
  Creates a new gauge metric.

  ## Examples

      iex> MetricsEx.Metric.gauge(:queue_depth, 42, %{queue: "sno_validation"})
      %MetricsEx.Metric{name: :queue_depth, type: :gauge, value: 42, tags: %{queue: "sno_validation"}}
  """
  @spec gauge(atom(), number(), tags(), map()) :: t()
  def gauge(name, value, tags \\ %{}, metadata \\ %{}) do
    %__MODULE__{
      name: name,
      type: :gauge,
      value: value,
      tags: tags,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  @doc """
  Creates a new histogram metric.

  ## Examples

      iex> MetricsEx.Metric.histogram(:response_time, 123.45, %{endpoint: "/api/v1"})
      %MetricsEx.Metric{name: :response_time, type: :histogram, value: 123.45, tags: %{endpoint: "/api/v1"}}
  """
  @spec histogram(atom(), number(), tags(), map()) :: t()
  def histogram(name, value, tags \\ %{}, metadata \\ %{}) do
    %__MODULE__{
      name: name,
      type: :histogram,
      value: value,
      tags: tags,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  @doc """
  Creates a metric from a telemetry event.

  ## Examples

      iex> MetricsEx.Metric.from_telemetry(
      ...>   [:work, :job, :completed],
      ...>   %{duration: 1234},
      ...>   %{tenant: "cns"}
      ...> )
      %MetricsEx.Metric{name: :work_job_completed_duration, type: :histogram, ...}
  """
  @spec from_telemetry(list(atom()), map(), map()) :: t()
  def from_telemetry(event_name, measurements, metadata) do
    name = event_name |> Enum.join("_") |> String.to_atom()

    # Default to histogram for duration-like measurements
    type = if Map.has_key?(measurements, :duration), do: :histogram, else: :counter
    value = measurements[:duration] || measurements[:count] || 1

    %__MODULE__{
      name: name,
      type: type,
      value: value,
      tags: MetricsEx.Tagging.extract(metadata),
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  @doc """
  Converts metric to map format suitable for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = metric) do
    %{
      name: metric.name,
      type: metric.type,
      value: metric.value,
      tags: metric.tags,
      timestamp: DateTime.to_iso8601(metric.timestamp),
      metadata: metric.metadata
    }
  end
end

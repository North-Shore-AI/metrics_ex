defmodule MetricsEx.Exporters.OpenTelemetry do
  @moduledoc """
  Exports metrics in OpenTelemetry format (OTLP).

  Provides compatibility with OpenTelemetry observability framework
  and OTLP-compatible backends (Jaeger, Zipkin, etc.).

  See: https://opentelemetry.io/docs/specs/otlp/
  """

  alias MetricsEx.Metric
  alias MetricsEx.Storage.ETS

  @doc """
  Exports all metrics in OpenTelemetry JSON format.

  Returns a map structure compatible with OTLP/JSON encoding.

  ## Examples

      iex> MetricsEx.Exporters.OpenTelemetry.export()
      %{
        resource_metrics: [
          %{
            scope_metrics: [
              %{
                metrics: [...]
              }
            ]
          }
        ]
      }
  """
  @spec export() :: map()
  def export do
    metrics =
      ETS.all()
      |> Enum.map(fn {_key, metric} -> metric end)

    to_otlp_format(metrics)
  end

  @doc """
  Exports metrics for a specific metric name in OpenTelemetry format.
  """
  @spec export(atom()) :: map()
  def export(metric_name) do
    metrics = ETS.query(name: metric_name)
    to_otlp_format(metrics)
  end

  @doc """
  Converts metrics to OTLP (OpenTelemetry Protocol) format.

  Follows the OTLP/JSON specification for metrics.
  """
  @spec to_otlp_format(list(Metric.t())) :: map()
  def to_otlp_format(metrics) do
    grouped_metrics =
      metrics
      |> Enum.group_by(& &1.name)
      |> Enum.map(fn {name, metric_list} ->
        convert_metric_group(name, metric_list)
      end)

    %{
      resource_metrics: [
        %{
          resource: %{
            attributes: [
              %{key: "service.name", value: %{string_value: "metrics_ex"}},
              %{key: "service.version", value: %{string_value: "0.1.0"}}
            ]
          },
          scope_metrics: [
            %{
              scope: %{
                name: "MetricsEx",
                version: "0.1.0"
              },
              metrics: grouped_metrics
            }
          ]
        }
      ]
    }
  end

  @doc """
  Converts a metric to OpenTelemetry JSON attributes format.
  """
  @spec to_attributes(Metric.t()) :: list(map())
  def to_attributes(%Metric{} = metric) do
    metric.tags
    |> Enum.map(fn {key, value} ->
      %{
        key: to_string(key),
        value: attribute_value(value)
      }
    end)
  end

  # Private functions

  defp convert_metric_group(name, metric_list) do
    # Get the type from the first metric (they should all be the same type)
    metric_type = hd(metric_list).type

    data_points =
      Enum.map(metric_list, fn metric ->
        %{
          attributes: to_attributes(metric),
          time_unix_nano: DateTime.to_unix(metric.timestamp, :nanosecond),
          value: metric.value
        }
      end)

    metric_data =
      case metric_type do
        :counter ->
          %{
            sum: %{
              data_points: data_points,
              aggregation_temporality: 2,
              # CUMULATIVE
              is_monotonic: true
            }
          }

        :gauge ->
          %{
            gauge: %{
              data_points: data_points
            }
          }

        :histogram ->
          %{
            histogram: %{
              data_points:
                Enum.map(metric_list, fn metric ->
                  %{
                    attributes: to_attributes(metric),
                    time_unix_nano: DateTime.to_unix(metric.timestamp, :nanosecond),
                    count: 1,
                    sum: metric.value,
                    bucket_counts: [],
                    explicit_bounds: []
                  }
                end),
              aggregation_temporality: 2
              # CUMULATIVE
            }
          }
      end

    Map.merge(
      %{
        name: to_string(name),
        description: "Metric #{name}",
        unit: unit_for_type(metric_type)
      },
      metric_data
    )
  end

  defp attribute_value(value) when is_binary(value) do
    %{string_value: value}
  end

  defp attribute_value(value) when is_atom(value) do
    %{string_value: Atom.to_string(value)}
  end

  defp attribute_value(value) when is_integer(value) do
    %{int_value: value}
  end

  defp attribute_value(value) when is_float(value) do
    %{double_value: value}
  end

  defp attribute_value(value) when is_boolean(value) do
    %{bool_value: value}
  end

  defp attribute_value(value) do
    %{string_value: to_string(value)}
  end

  defp unit_for_type(:counter), do: "1"
  defp unit_for_type(:gauge), do: "1"
  defp unit_for_type(:histogram), do: "ms"
end

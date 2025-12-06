# MetricsEx Exporters Guide

This guide covers how to use the various metric exporters available in MetricsEx.

## Available Exporters

1. **Prometheus** - Text format for Prometheus scraping
2. **InfluxDB** - Line protocol for InfluxDB time-series database
3. **Datadog** - DogStatsD format for Datadog monitoring
4. **OpenTelemetry** - OTLP/JSON format for OpenTelemetry backends

## Prometheus Exporter

Export metrics in Prometheus text format for scraping.

### Usage

```elixir
# Export all metrics
text = MetricsEx.Storage.Prometheus.export()

# Export specific metric
text = MetricsEx.Storage.Prometheus.export(:jobs_completed)

# Use in Phoenix controller
defmodule MyAppWeb.MetricsController do
  use MyAppWeb, :controller

  def prometheus(conn, _params) do
    metrics = MetricsEx.Storage.Prometheus.export()

    conn
    |> put_resp_content_type(MetricsEx.Storage.Prometheus.content_type())
    |> send_resp(200, metrics)
  end
end
```

### Output Format

```
# HELP jobs_completed Jobs completed
# TYPE jobs_completed counter
jobs_completed{tenant="cns"} 1234 1638835200000
jobs_completed{tenant="crucible"} 567 1638835200000

# HELP queue_depth Queue depth
# TYPE queue_depth gauge
queue_depth{queue="sno_validation"} 42 1638835200000
```

### Prometheus Configuration

```yaml
scrape_configs:
  - job_name: 'metrics_ex'
    static_configs:
      - targets: ['localhost:4000']
    metrics_path: '/metrics/prometheus'
    scrape_interval: 15s
```

## InfluxDB Exporter

Export metrics in InfluxDB line protocol format.

### Usage

```elixir
# Export all metrics (default: nanosecond precision)
lines = MetricsEx.Exporters.InfluxDB.export()

# Export with millisecond precision
lines = MetricsEx.Exporters.InfluxDB.export_with_opts(precision: :millisecond)

# Export specific metric
lines = MetricsEx.Exporters.InfluxDB.export_metric(:response_time)

# Write to InfluxDB via HTTP
defmodule MyApp.InfluxWriter do
  def write_metrics do
    lines = MetricsEx.Exporters.InfluxDB.export()

    HTTPoison.post(
      "http://localhost:8086/write?db=metrics&precision=ns",
      lines,
      [{"Content-Type", "application/octet-stream"}]
    )
  end
end
```

### Output Format

```
jobs_completed,tenant=cns value=1234i 1638835200000000000
jobs_completed,tenant=crucible value=567i 1638835200000000000
queue_depth,queue=sno_validation value=42i 1638835200000000000
response_time,endpoint=/api value=123.45 1638835200000000000
```

### InfluxDB Setup

```bash
# Create database
curl -XPOST 'http://localhost:8086/query' --data-urlencode 'q=CREATE DATABASE metrics'

# Query data
curl -G 'http://localhost:8086/query?db=metrics' \
  --data-urlencode 'q=SELECT * FROM jobs_completed WHERE time > now() - 1h'
```

## Datadog Exporter

Export metrics in DogStatsD format for Datadog.

### Usage

```elixir
# Export all metrics as datagrams
datagrams = MetricsEx.Exporters.Datadog.export()
# => ["jobs_completed:1234|c|#tenant:cns", ...]

# Export specific metric
datagrams = MetricsEx.Exporters.Datadog.export(:queue_depth)

# Send to DogStatsD agent via UDP
{:ok, count} = MetricsEx.Exporters.Datadog.send_to_agent(
  host: ~c"localhost",
  port: 8125,
  namespace: "myapp"
)
```

### Output Format

```
jobs.completed:1234|c|#tenant:cns
jobs.completed:567|c|#tenant:crucible
queue.depth:42|g|#queue:sno_validation
response.time:123.45|h|#endpoint:/api
```

### Datadog Agent Configuration

```yaml
# datadog.yaml
dogstatsd_port: 8125
dogstatsd_non_local_traffic: true

# Tag metrics
tags:
  - env:production
  - service:metrics_ex
```

### Metric Types

- `c` - Counter (monotonically increasing)
- `g` - Gauge (point-in-time value)
- `h` - Histogram (distribution of values)

## OpenTelemetry Exporter

Export metrics in OTLP/JSON format for OpenTelemetry collectors.

### Usage

```elixir
# Export all metrics
otlp_data = MetricsEx.Exporters.OpenTelemetry.export()

# Export specific metric
otlp_data = MetricsEx.Exporters.OpenTelemetry.export(:jobs_completed)

# Send to OTLP collector
defmodule MyApp.OTLPExporter do
  def export_metrics do
    data = MetricsEx.Exporters.OpenTelemetry.export()
    json = Jason.encode!(data)

    HTTPoison.post(
      "http://localhost:4318/v1/metrics",
      json,
      [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_key}"}
      ]
    )
  end
end
```

### Output Format

```json
{
  "resource_metrics": [
    {
      "resource": {
        "attributes": [
          {"key": "service.name", "value": {"string_value": "metrics_ex"}},
          {"key": "service.version", "value": {"string_value": "0.1.0"}}
        ]
      },
      "scope_metrics": [
        {
          "scope": {"name": "MetricsEx", "version": "0.1.0"},
          "metrics": [
            {
              "name": "jobs_completed",
              "description": "Metric jobs_completed",
              "unit": "1",
              "sum": {
                "data_points": [...],
                "aggregation_temporality": 2,
                "is_monotonic": true
              }
            }
          ]
        }
      ]
    }
  ]
}
```

### OpenTelemetry Collector Configuration

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
  jaeger:
    endpoint: jaeger-all-in-one:14250

service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [prometheus, jaeger]
```

## Periodic Export Example

Set up scheduled metric exports:

```elixir
defmodule MyApp.MetricsExporter do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Export every 60 seconds
    schedule_export()
    {:ok, %{}}
  end

  def handle_info(:export, state) do
    # Export to InfluxDB
    lines = MetricsEx.Exporters.InfluxDB.export()
    write_to_influx(lines)

    # Export to Datadog
    {:ok, _count} = MetricsEx.Exporters.Datadog.send_to_agent()

    schedule_export()
    {:noreply, state}
  end

  defp schedule_export do
    Process.send_after(self(), :export, :timer.seconds(60))
  end

  defp write_to_influx(lines) do
    # Your InfluxDB write logic
  end
end
```

## Best Practices

1. **Batching**: Export metrics in batches (e.g., every 60 seconds) rather than on every metric recording
2. **Error Handling**: Wrap exports in try/catch to prevent failures from affecting metric collection
3. **Buffering**: Consider buffering exports if the target system is temporarily unavailable
4. **Sampling**: For high-volume metrics, consider sampling exports (e.g., 1 in 100)
5. **Namespacing**: Use metric namespaces to organize metrics by application/service

## Troubleshooting

### Prometheus

**Issue**: Metrics not appearing in Prometheus
- Check scrape target is accessible
- Verify `scrape_interval` matches export frequency
- Check Prometheus logs for scrape errors

### InfluxDB

**Issue**: Line protocol parse errors
- Verify tag/field value escaping
- Check timestamp precision matches InfluxDB configuration
- Test with a single metric first

### Datadog

**Issue**: Metrics not showing in Datadog UI
- Verify DogStatsD agent is running (`sudo service datadog-agent status`)
- Check agent logs: `/var/log/datadog/agent.log`
- Verify UDP port 8125 is accessible

### OpenTelemetry

**Issue**: Collector not receiving metrics
- Verify collector is running and accessible
- Check collector logs for errors
- Validate OTLP endpoint configuration
- Test with `curl` to verify collector HTTP endpoint

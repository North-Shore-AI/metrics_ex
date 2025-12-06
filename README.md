# MetricsEx

[![Elixir CI](https://github.com/North-Shore-AI/metrics_ex/actions/workflows/elixir.yml/badge.svg)](https://github.com/North-Shore-AI/metrics_ex/actions/workflows/elixir.yml)

Centralized metrics aggregation service for experiment results and system health.

## Purpose

MetricsEx provides comprehensive metrics collection, aggregation, and querying for:

- **Experiment results** (Crucible)
- **Model performance** (CNS agents)
- **System health** (Work jobs, services)
- **Training progress** (Tinkex)

## Features

- **Multiple metric types**: counters, gauges, histograms
- **Fast in-memory storage**: ETS-based with configurable retention
- **Flexible aggregations**: mean, sum, count, min, max, percentiles
- **Time series support**: Fixed interval buckets (minute, hour, day)
- **Telemetry integration**: Auto-attach to telemetry events
- **Export formats**: JSON API, Prometheus text format
- **Real-time streaming**: Phoenix PubSub integration
- **Dashboard-ready**: Pre-computed rollups for UI consumption

## Installation

Add `metrics_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:metrics_ex, "~> 0.1.0"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :metrics_ex,
  retention_hours: 24,
  pubsub: MyApp.PubSub  # Optional: for real-time streaming
```

## Quick Start

### Recording Metrics

```elixir
# Record experiment results
MetricsEx.record(:experiment_result, %{
  experiment_id: "exp_123",
  metric: :entailment_score,
  value: 0.75,
  tags: %{model: "llama-3.1", dataset: "scifact"}
})

# Increment counters
MetricsEx.increment(:jobs_completed, tags: %{tenant: "cns"})
MetricsEx.increment(:requests_total, 5, tags: %{endpoint: "/api"})

# Record gauge values (point-in-time)
MetricsEx.gauge(:queue_depth, 42, tags: %{queue: "sno_validation"})

# Record histogram values (distributions)
MetricsEx.histogram(:response_time, 123.45, tags: %{endpoint: "/api"})

# Measure execution time
result = MetricsEx.measure(:database_query, fn ->
  # expensive operation
  MyApp.run_query()
end, tags: %{query: "SELECT"})
```

### Querying Metrics

```elixir
# Get raw metrics
MetricsEx.get_metrics(name: :jobs_completed, limit: 100)
# => %{metrics: [...], count: 100, timestamp: "2025-12-06T..."}

# Aggregate with grouping
MetricsEx.query(:experiment_result,
  group_by: [:model],
  aggregation: :mean,
  window: :last_24h
)
# => [
#   %{model: "llama-3.1", mean: 0.72},
#   %{model: "qwen", mean: 0.68}
# ]

# Time series data
MetricsEx.time_series(:jobs_completed,
  interval: :hour,
  aggregation: :count,
  window: :last_24h
)
# => [
#   %{timestamp: ~U[2025-12-06 00:00:00Z], count: 45},
#   %{timestamp: ~U[2025-12-06 01:00:00Z], count: 52},
#   ...
# ]

# Pre-computed rollups for dashboards
MetricsEx.rollup(:experiment_result,
  group_by: [:model, :dataset],
  aggregations: [:mean, :count, :p95],
  window: :last_24h
)
# => %{
#   "llama-3.1/scifact" => %{mean: 0.72, count: 150, p95: 0.89},
#   "qwen/fever" => %{mean: 0.68, count: 200, p95: 0.85}
# }
```

### Telemetry Integration

```elixir
# Attach to telemetry events
MetricsEx.attach_telemetry([
  {[:work, :job, :completed], :counter},
  {[:work, :job, :duration], :histogram},
  {[:crucible, :experiment, :completed], :histogram},
  {[:queue, :depth], :gauge}
])

# Now telemetry events are automatically recorded
:telemetry.execute([:work, :job, :completed], %{count: 1}, %{tenant: "cns"})
```

### Prometheus Export

```elixir
# Export all metrics in Prometheus format
prometheus_text = MetricsEx.Storage.Prometheus.export()

# Export specific metric
prometheus_text = MetricsEx.Storage.Prometheus.export(:jobs_completed)

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

## Architecture

### Supervision Tree

```
MetricsEx.Supervisor
├── Phoenix.PubSub (optional)
├── MetricsEx.Storage.ETS (storage backend)
└── MetricsEx.Recorder (recording coordinator)
```

### Components

#### 1. Metric Types (`MetricsEx.Metric`)
Defines three core metric types:
- **Counter**: Monotonically increasing (e.g., request count, jobs completed)
- **Gauge**: Point-in-time value (e.g., queue depth, memory usage)
- **Histogram**: Distribution of values (e.g., response times, scores)

#### 2. Storage Backend (`MetricsEx.Storage.ETS`)
- Fast in-memory ETS storage
- Configurable retention (default: 24 hours)
- Automatic cleanup of old metrics
- Concurrent reads/writes

#### 3. Recorder (`MetricsEx.Recorder`)
- GenServer for recording metrics
- Real-time PubSub broadcasting
- Type inference based on metric name/value

#### 4. Aggregator (`MetricsEx.Aggregator`)
- Flexible aggregation functions: mean, sum, count, min, max, percentiles
- Group by tags
- Time series generation
- Pre-computed rollups

#### 5. Telemetry Handler (`MetricsEx.TelemetryHandler`)
- Auto-attach to telemetry events
- Converts telemetry measurements to metrics
- Extracts tags from metadata

#### 6. API (`MetricsEx.API`)
- JSON-compatible data structures
- Dashboard-ready endpoints
- Time window helpers

## Aggregation Functions

| Function | Description | Example |
|----------|-------------|---------|
| `:count` | Number of metrics | `count: 150` |
| `:sum` | Total sum of values | `sum: 1234` |
| `:mean` | Average value | `mean: 0.72` |
| `:min` | Minimum value | `min: 0.45` |
| `:max` | Maximum value | `max: 0.95` |
| `:p50` | 50th percentile (median) | `p50: 0.70` |
| `:p95` | 95th percentile | `p95: 0.89` |
| `:p99` | 99th percentile | `p99: 0.93` |

## Time Windows

| Window | Description |
|--------|-------------|
| `:last_hour` | Last 60 minutes |
| `:last_24h` | Last 24 hours |
| `:last_7d` | Last 7 days |
| `:last_30d` | Last 30 days |

## Time Intervals

| Interval | Description |
|----------|-------------|
| `:minute` | 1-minute buckets |
| `:hour` | 1-hour buckets |
| `:day` | 1-day buckets |

## System Statistics

```elixir
MetricsEx.get_stats()
# => %{
#   storage: %{
#     total_metrics: 12345,
#     metrics_stored: 12345,
#     metrics_pruned: 567,
#     retention_hours: 24,
#     memory_bytes: 1048576
#   },
#   recorder: %{
#     metrics_recorded: 12345
#   },
#   timestamp: "2025-12-06T12:00:00Z"
# }
```

## Integration Examples

### With Crucible Experiments

```elixir
# Record experiment metrics
MetricsEx.record(:crucible_experiment, %{
  value: entailment_score,
  tags: %{
    experiment_id: experiment.id,
    model: "llama-3.1",
    dataset: "scifact",
    stage: "validation"
  }
})

# Query experiment results
MetricsEx.query(:crucible_experiment,
  group_by: [:model, :dataset],
  aggregation: :mean,
  window: :last_7d
)
```

### With CNS Agents

```elixir
# Record agent performance
MetricsEx.record(:cns_agent_metric, %{
  value: beta1_score,
  tags: %{
    agent: "antagonist",
    sno_id: sno.id,
    iteration: 3
  }
})

# Track agent iterations
MetricsEx.time_series(:cns_agent_metric,
  interval: :hour,
  aggregation: :mean,
  tags: %{agent: "synthesizer"},
  window: :last_24h
)
```

### With Work Job System

```elixir
# Auto-record via telemetry
:telemetry.execute(
  [:work, :job, :completed],
  %{duration: job_duration_ms},
  %{tenant: tenant, queue: queue_name}
)

# Monitor job throughput
MetricsEx.rollup(:work_job_completed,
  group_by: [:tenant, :queue],
  aggregations: [:count, :mean, :p95],
  window: :last_hour
)
```

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/metrics_ex/aggregator_test.exs
```

## Performance

- **Write throughput**: 100K+ metrics/sec (async casts to GenServer)
- **Query latency**: <10ms for typical aggregations (in-memory ETS)
- **Memory footprint**: ~100 bytes per metric + overhead
- **Retention cleanup**: Every 5 minutes (configurable)

## Roadmap

- [ ] Persistent storage backend (PostgreSQL, ClickHouse)
- [ ] Advanced percentile algorithms (t-digest)
- [ ] Alert rules and notifications
- [ ] Metric cardinality limits
- [ ] Query result caching
- [ ] Grafana integration
- [ ] OpenTelemetry compatibility

## Contributing

This project is part of the [North-Shore-AI](https://github.com/North-Shore-AI) monorepo. See the main repository for contribution guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Related Projects

- [crucible_framework](https://github.com/North-Shore-AI/crucible_framework) - ML experimentation orchestration
- [cns](https://github.com/North-Shore-AI/cns) - Critic-Network Synthesis
- [crucible_telemetry](https://github.com/North-Shore-AI/crucible_telemetry) - Research-grade instrumentation
- [ex_work](https://github.com/North-Shore-AI/ex_work) - Background job processing

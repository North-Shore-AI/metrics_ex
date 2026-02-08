# Changelog

All notable changes to MetricsEx will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-02-08

### Added

- **`MetricsEx.Tagging`** - Centralized tag extraction with standard lineage dimensions (`work_id`, `trace_id`, `plan_id`, `step_id`) plus existing tag keys (`tenant`, `model`, `dataset`, etc.)
- **Standard dimension propagation** - Lineage dimensions from metadata are automatically promoted into metric tags across `Recorder`, `Metric.from_telemetry/3`, and `TelemetryHandler`
- Telemetry handler tests (`test/metrics_ex/telemetry_handler_test.exs`)
- Tests for standard dimension propagation in `MetricTest` and `RecorderTest`
- Standard Dimensions section in README and EXPORTERS.md
- HexDocs module groups (Core, Storage, Exporters, Utilities) in `mix.exs`

### Changed

- Consolidated duplicate `extract_tags/1` from `Metric` and `TelemetryHandler` into `MetricsEx.Tagging`
- `Recorder.increment/3`, `gauge/3`, `histogram/3`, and `record/2` now call `Tagging.merge_tags/2` to promote standard dimensions
- Upgraded `ex_doc` dependency from `~> 0.30` to `~> 0.40.0`
- Package files now include `guides` and `examples` directories
- Replaced TODO comments in `Alerting` with note about downstream integrations

## [0.1.0] - 2025-12-06

### Added

- Initial release
- Core metric types: counter, gauge, histogram
- ETS-based storage with configurable retention
- Aggregation functions: mean, sum, count, min, max, p50, p95, p99
- Time series support with minute/hour/day intervals
- Telemetry integration for automatic event capture
- Prometheus text format export
- JSON API for dashboards
- Threshold-based alerting with Z-score and IQR anomaly detection
- Phoenix PubSub integration for real-time streaming
- Standard tag dimensions (work_id, trace_id, plan_id, step_id)
- Rollups for pre-computed aggregations

defmodule MetricsEx.AggregatorTest do
  use ExUnit.Case, async: false
  alias MetricsEx.{Aggregator, Storage.ETS, Metric}

  setup do
    ETS.clear()

    # Seed test data
    ETS.store(Metric.counter(:jobs_completed, 10, %{tenant: "cns"}))
    ETS.store(Metric.counter(:jobs_completed, 20, %{tenant: "cns"}))
    ETS.store(Metric.counter(:jobs_completed, 30, %{tenant: "crucible"}))
    ETS.store(Metric.histogram(:response_time, 100.0, %{endpoint: "/api"}))
    ETS.store(Metric.histogram(:response_time, 200.0, %{endpoint: "/api"}))
    ETS.store(Metric.histogram(:response_time, 150.0, %{endpoint: "/api"}))

    :ok
  end

  describe "query/2 with aggregations" do
    test "calculates count" do
      result = Aggregator.query(:jobs_completed, aggregation: :count)
      assert result == 3
    end

    test "calculates sum" do
      result = Aggregator.query(:jobs_completed, aggregation: :sum)
      assert result == 60
    end

    test "calculates mean" do
      result = Aggregator.query(:response_time, aggregation: :mean)
      assert_in_delta result, 150.0, 0.1
    end

    test "calculates min" do
      result = Aggregator.query(:response_time, aggregation: :min)
      assert result == 100.0
    end

    test "calculates max" do
      result = Aggregator.query(:response_time, aggregation: :max)
      assert result == 200.0
    end

    test "calculates p95" do
      result = Aggregator.query(:response_time, aggregation: :p95)
      assert result >= 150.0
    end
  end

  describe "query/2 with grouping" do
    test "groups by single field" do
      results =
        Aggregator.query(:jobs_completed,
          group_by: [:tenant],
          aggregation: :sum
        )

      assert length(results) == 2
      tenant_sums = Enum.into(results, %{}, fn r -> {r.tenant, r.sum} end)
      assert tenant_sums["cns"] == 30
      assert tenant_sums["crucible"] == 30
    end

    test "groups by multiple fields" do
      ETS.store(Metric.counter(:test, 1, %{model: "llama", dataset: "scifact"}))
      ETS.store(Metric.counter(:test, 2, %{model: "llama", dataset: "fever"}))

      results =
        Aggregator.query(:test,
          group_by: [:model, :dataset],
          aggregation: :sum
        )

      assert length(results) == 2
    end
  end

  describe "time_series/2" do
    test "creates hourly time series" do
      now = DateTime.utc_now()
      # 2 hours ago
      past = DateTime.add(now, -7200, :second)

      results =
        Aggregator.time_series(:jobs_completed,
          interval: :hour,
          aggregation: :count,
          time_range: {past, now}
        )

      assert is_list(results)

      assert Enum.all?(results, fn point ->
               Map.has_key?(point, :timestamp) && Map.has_key?(point, :count)
             end)
    end
  end

  describe "rollup/2" do
    test "calculates rollups with multiple aggregations" do
      rollups =
        Aggregator.rollup(:jobs_completed,
          group_by: [:tenant],
          aggregations: [:sum, :count, :mean],
          window: :last_24h
        )

      assert is_map(rollups)
      assert Map.has_key?(rollups, "cns")

      cns_rollup = rollups["cns"]
      assert cns_rollup.sum == 30
      assert cns_rollup.count == 2
      assert cns_rollup.mean == 15.0
    end
  end
end

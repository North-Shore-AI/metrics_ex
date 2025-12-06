defmodule MetricsEx.Storage.ETSTest do
  use ExUnit.Case, async: false
  alias MetricsEx.{Metric, Storage.ETS}

  setup do
    # Clear storage before each test
    ETS.clear()
    :ok
  end

  describe "store/1" do
    test "stores a metric in ETS" do
      metric = Metric.counter(:test_counter, 1, %{tenant: "cns"})
      assert :ok = ETS.store(metric)

      results = ETS.query(name: :test_counter)
      assert length(results) == 1
      assert hd(results).name == :test_counter
    end

    test "stores multiple metrics with same name" do
      metric1 = Metric.counter(:test_counter, 1, %{tenant: "cns"})
      metric2 = Metric.counter(:test_counter, 2, %{tenant: "crucible"})

      ETS.store(metric1)
      ETS.store(metric2)

      results = ETS.query(name: :test_counter)
      assert length(results) == 2
    end
  end

  describe "query/1" do
    test "queries by metric name" do
      ETS.store(Metric.counter(:counter_a, 1))
      ETS.store(Metric.counter(:counter_b, 2))

      results = ETS.query(name: :counter_a)
      assert length(results) == 1
      assert hd(results).name == :counter_a
    end

    test "queries by metric type" do
      ETS.store(Metric.counter(:metric1, 1))
      ETS.store(Metric.gauge(:metric2, 42))

      results = ETS.query(type: :gauge)
      assert length(results) == 1
      assert hd(results).type == :gauge
    end

    test "queries by tags" do
      ETS.store(Metric.counter(:test, 1, %{tenant: "cns"}))
      ETS.store(Metric.counter(:test, 2, %{tenant: "crucible"}))

      results = ETS.query(name: :test, tags: %{tenant: "cns"})
      assert length(results) == 1
      assert hd(results).tags.tenant == "cns"
    end

    test "queries with time range" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      ETS.store(Metric.counter(:test, 1))

      results = ETS.query(name: :test, since: past, until: future)
      assert length(results) == 1
    end

    test "limits results" do
      for i <- 1..10 do
        ETS.store(Metric.counter(:test, i))
      end

      results = ETS.query(name: :test, limit: 5)
      assert length(results) == 5
    end
  end

  describe "stats/0" do
    test "returns storage statistics" do
      ETS.store(Metric.counter(:test, 1))

      stats = ETS.stats()
      assert stats.total_metrics >= 1
      assert stats.metrics_stored >= 1
      assert is_integer(stats.memory_bytes)
    end
  end

  describe "clear/0" do
    test "clears all metrics" do
      ETS.store(Metric.counter(:test, 1))
      ETS.clear()

      results = ETS.all()
      assert results == []
    end
  end
end

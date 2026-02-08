defmodule MetricsEx.TelemetryHandlerTest do
  use ExUnit.Case, async: false

  alias MetricsEx.Storage.ETS
  alias MetricsEx.TelemetryHandler

  setup do
    ETS.clear()
    handler_id = :"metrics_ex_test_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    {:ok, handler_id: handler_id}
  end

  test "propagates standard dimensions from telemetry metadata", %{handler_id: handler_id} do
    TelemetryHandler.attach_telemetry(
      [{[:work, :job, :completed], :counter}],
      handler_id: handler_id
    )

    :telemetry.execute(
      [:work, :job, :completed],
      %{count: 1},
      %{
        work_id: "work-222",
        trace_id: "trace-222",
        plan_id: "plan-222",
        step_id: "step-222",
        tenant: "cns"
      }
    )

    Process.sleep(50)

    results = ETS.query(name: :work_job_completed)
    assert length(results) == 1

    metric = hd(results)
    assert metric.tags.work_id == "work-222"
    assert metric.tags.trace_id == "trace-222"
    assert metric.tags.plan_id == "plan-222"
    assert metric.tags.step_id == "step-222"
    assert metric.tags.tenant == "cns"
  end
end

defmodule HubspotClient.PipelinesTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Pipelines

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/3 returns a plain list with atom keys", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/deals"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => "default",
            "label" => "Sales Pipeline",
            "displayOrder" => 0,
            "createdAt" => "2026-01-01T00:00:00Z",
            "stages" => [
              %{
                "id" => "appointmentscheduled",
                "label" => "Appointment Scheduled",
                "displayOrder" => 0,
                "metadata" => %{"isClosed" => "false", "probability" => "0.2"}
              }
            ]
          }
        ]
      })
    end)

    assert {:ok, [pipeline]} = Pipelines.list(client, "deals")
    assert pipeline.id == "default"
    assert pipeline.label == "Sales Pipeline"
    assert pipeline.display_order == 0
    assert pipeline.created_at == ~U[2026-01-01 00:00:00Z]
    assert [stage] = pipeline.stages
    assert stage.label == "Appointment Scheduled"
    assert stage.metadata.is_closed == "false"
  end

  test "list/3 works for tickets", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/tickets"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert {:ok, []} = Pipelines.list(client, "tickets")
  end

  test "get/4 reads a single pipeline", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/deals/default"
      Req.Test.json(conn, %{"id" => "default", "label" => "Sales Pipeline"})
    end)

    assert {:ok, %{id: "default", label: "Sales Pipeline"}} =
             Pipelines.get(client, "deals", "default")
  end

  test "stages/4 lists a pipeline's stages", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/deals/default/stages"
      Req.Test.json(conn, %{"results" => [%{"id" => "1", "label" => "Appointment"}]})
    end)

    assert {:ok, [%{id: "1", label: "Appointment"}]} =
             Pipelines.stages(client, "deals", "default")
  end

  test "percent-encodes pipeline ids that need it", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/pipelines/deals/a%20b/stages"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert {:ok, []} = Pipelines.stages(client, "deals", "a b")
  end

  test "propagates errors", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "missing scope"})
    end)

    assert {:error, %HubspotClient.Error{status: 403}} = Pipelines.list(client, "deals")
  end
end

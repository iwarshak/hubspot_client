defmodule HubspotClient.RequestTest do
  use ExUnit.Case, async: true

  alias HubspotClient.{Error, Request}

  setup do
    client =
      HubspotClient.new(
        token: "test-token",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  describe "get/3" do
    test "sends a bearer token and hits the expected path", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/crm/v3/objects/deals"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-token"]
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, %{"results" => []}} = Request.get(client, "/crm/v3/objects/deals")
    end

    test "encodes query params", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["limit"] == "100"
        assert conn.query_params["properties"] == "dealname,amount"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} =
               Request.get(client, "/crm/v3/objects/deals",
                 limit: 100,
                 properties: "dealname,amount"
               )
    end

    test "returns an Error struct on a 4xx", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{
          "message" => "resource not found",
          "category" => "OBJECT_NOT_FOUND",
          "correlationId" => "abc-123"
        })
      end)

      assert {:error,
              %Error{status: 404, category: "OBJECT_NOT_FOUND", correlation_id: "abc-123"}} =
               Request.get(client, "/crm/v3/objects/deals/nope")
    end

    test "returns an Error struct on a 5xx", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "boom"})
      end)

      assert {:error, %Error{status: 500, message: "boom"}} =
               Request.get(client, "/crm/v3/objects/deals")
    end

    test "passes transport errors through unwrapped", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               Request.get(client, "/crm/v3/objects/deals")
    end

    test "req_options override library defaults" do
      client =
        HubspotClient.new(
          token: "t",
          req_options: [
            plug: {Req.Test, HubspotClient},
            retry: false,
            headers: [{"x-custom", "1"}]
          ]
        )

      Req.Test.stub(HubspotClient, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-custom") == ["1"]
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} = Request.get(client, "/crm/v3/objects/deals")
    end

    test "sends no query string when no params are given", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.query_string == ""
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} = Request.get(client, "/crm/v3/objects/deals")
    end

    test "req_options cannot change the HTTP method of a GET" do
      client =
        HubspotClient.new(
          token: "t",
          req_options: [plug: {Req.Test, HubspotClient}, retry: false, method: :delete]
        )

      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.method == "GET"
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} = Request.get(client, "/crm/v3/objects/deals")
    end

    test "req_options cannot smuggle a body into a GET" do
      client =
        HubspotClient.new(
          token: "t",
          req_options: [plug: {Req.Test, HubspotClient}, retry: false, json: %{"evil" => true}]
        )

      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.method == "GET"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == ""
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} = Request.get(client, "/crm/v3/objects/deals")
    end

    test "a 200 with a non-map body returns an error instead of raising", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html>hi</html>")
      end)

      assert {:error, %Error{status: 200}} = Request.get(client, "/crm/v3/objects/deals")
    end
  end

  describe "post/3" do
    test "sends a JSON body", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/crm/v3/objects/deals/search"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"limit" => 10}
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, %{"results" => []}} =
               Request.post(client, "/crm/v3/objects/deals/search", %{"limit" => 10})
    end

    test "allows the batch-read endpoint", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/p12345_widget/batch/read"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} =
               Request.post(client, "/crm/v3/objects/p12345_widget/batch/read", %{"inputs" => []})
    end

    for path <- [
          "/crm/v3/objects/deals",
          "/crm/v3/objects/deals/batch/create",
          "/crm/v3/objects/deals/batch/update",
          "/crm/v3/objects/deals/batch/archive",
          "/crm/v3/objects/deals/merge",
          "/crm/v4/associations/deals/companies/batch/create",
          "/crm/v3/objects/deals/search/../batch/create",
          "/crm/v3/objects/deals/search?x=1",
          "/crm/v3/objects/deals/batch/read/../create"
        ] do
      test "refuses the write-shaped POST path #{path} without sending a request", %{
        client: client
      } do
        Req.Test.stub(HubspotClient, fn _conn ->
          flunk("request must not be sent")
        end)

        assert_raise ArgumentError, ~r/read-only/, fn ->
          Request.post(client, unquote(path), %{"properties" => %{"dealname" => "x"}})
        end
      end
    end
  end

  describe "telemetry" do
    test "emits rate-limit event on 200 with all three headers", %{client: client} do
      handler_id = "test_rate_limit_200"
      ref = make_ref()

      :telemetry.attach(
        handler_id,
        [:hubspot_client, :rate_limit],
        fn _event, measurements, metadata, _ ->
          send(self(), {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-remaining", "189")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-max", "190")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-interval-milliseconds", "10000")
        |> Req.Test.json(%{"results" => []})
      end)

      assert {:ok, %{"results" => []}} = Request.get(client, "/crm/v3/objects/deals")

      assert_receive {:telemetry, ^ref, measurements, metadata}
      assert measurements == %{remaining: 189, max: 190, interval_ms: 10_000}
      assert metadata.method == :get
      assert metadata.path == "/crm/v3/objects/deals"
      assert metadata.status == 200
    end

    test "emits rate-limit event on 429 with headers", %{client: client} do
      handler_id = "test_rate_limit_429"
      ref = make_ref()

      :telemetry.attach(
        handler_id,
        [:hubspot_client, :rate_limit],
        fn _event, measurements, metadata, _ ->
          send(self(), {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-remaining", "0")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-max", "190")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-interval-milliseconds", "10000")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"message" => "rate limited"})
      end)

      assert {:error, %Error{status: 429}} = Request.get(client, "/crm/v3/objects/deals")

      assert_receive {:telemetry, ^ref, measurements, metadata}
      assert measurements == %{remaining: 0, max: 190, interval_ms: 10_000}
      assert metadata.method == :get
      assert metadata.path == "/crm/v3/objects/deals"
      assert metadata.status == 429
    end

    test "does not emit event when no rate-limit headers present", %{client: client} do
      handler_id = "test_rate_limit_no_headers"
      ref = make_ref()

      :telemetry.attach(
        handler_id,
        [:hubspot_client, :rate_limit],
        fn _event, _measurements, _metadata, _ ->
          send(self(), {:telemetry, ref})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      Req.Test.stub(HubspotClient, fn conn ->
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, %{"results" => []}} = Request.get(client, "/crm/v3/objects/deals")

      refute_receive {:telemetry, ^ref}, 100
    end

    test "emits only keys that parsed from headers", %{client: client} do
      handler_id = "test_rate_limit_partial"
      ref = make_ref()

      :telemetry.attach(
        handler_id,
        [:hubspot_client, :rate_limit],
        fn _event, measurements, metadata, _ ->
          send(self(), {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-remaining", "50")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-max", "not-a-number")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-interval-milliseconds", "10000")
        |> Req.Test.json(%{"results" => []})
      end)

      assert {:ok, %{"results" => []}} = Request.get(client, "/crm/v3/objects/deals")

      assert_receive {:telemetry, ^ref, measurements, metadata}
      assert measurements == %{remaining: 50, interval_ms: 10_000}
      refute Map.has_key?(measurements, :max)
      assert metadata.status == 200
    end

    test "request returns normal result when no handler attached", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-remaining", "189")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-max", "190")
        |> Plug.Conn.put_resp_header("x-hubspot-ratelimit-interval-milliseconds", "10000")
        |> Req.Test.json(%{"results" => []})
      end)

      assert {:ok, %{"results" => []}} = Request.get(client, "/crm/v3/objects/deals")
    end
  end
end

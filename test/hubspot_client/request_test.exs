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
  end
end

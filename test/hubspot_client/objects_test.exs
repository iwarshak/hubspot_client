defmodule HubspotClient.ObjectsTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Objects

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  describe "list/3" do
    test "requests the object collection and decodes the page", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/deals"

        Req.Test.json(conn, %{
          "results" => [
            %{"id" => "1", "properties" => %{"dealname" => "Acme"}},
            %{"id" => "2", "properties" => %{"dealname" => "Globex"}}
          ],
          "paging" => %{"next" => %{"after" => "NTI1"}}
        })
      end)

      assert {:ok, %{results: results, after: "NTI1"}} = Objects.list(client, "deals")
      assert [%{id: "1", properties: %{"dealname" => "Acme"}}, %{id: "2"}] = results
    end

    test "comma-joins list-valued params and camelCases propertiesWithHistory", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["properties"] == "dealname,amount"
        assert conn.query_params["associations"] == "companies,contacts"
        assert conn.query_params["propertiesWithHistory"] == "dealstage"
        assert conn.query_params["limit"] == "50"
        assert conn.query_params["after"] == "NTI1"
        assert conn.query_params["archived"] == "false"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} =
               Objects.list(client, "deals",
                 properties: ["dealname", "amount"],
                 associations: ["companies", "contacts"],
                 properties_with_history: ["dealstage"],
                 limit: 50,
                 after: "NTI1",
                 archived: false
               )
    end

    test "omits params that were not given", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.query_string == ""
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} = Objects.list(client, "deals")
    end

    test "ignores unknown options rather than forwarding them", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.query_string == ""
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} = Objects.list(client, "deals", nonsense: "value")
    end

    test "works for custom object types", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/p12345_widget"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, _} = Objects.list(client, "p12345_widget")
    end

    test "propagates errors", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "no scope"})
      end)

      assert {:error, %HubspotClient.Error{status: 403}} = Objects.list(client, "deals")
    end
  end

  describe "get/4" do
    test "requests a single object and decodes it", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/deals/123"
        Req.Test.json(conn, %{"id" => "123", "properties" => %{"dealname" => "Acme"}})
      end)

      assert {:ok, %{id: "123", properties: %{"dealname" => "Acme"}}} =
               Objects.get(client, "deals", "123")
    end

    test "accepts an integer id", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/deals/123"
        Req.Test.json(conn, %{"id" => "123"})
      end)

      assert {:ok, _} = Objects.get(client, "deals", 123)
    end

    test "percent-encodes ids that need it", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/contacts/a%20b"
        Req.Test.json(conn, %{"id" => "a b"})
      end)

      assert {:ok, _} = Objects.get(client, "contacts", "a b")
    end
  end
end

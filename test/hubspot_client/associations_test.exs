defmodule HubspotClient.AssociationsTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Associations

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/5 hits the v4 associations path and decodes a page", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v4/objects/deals/123/associations/companies"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "toObjectId" => 456,
            "associationTypes" => [
              %{"category" => "HUBSPOT_DEFINED", "typeId" => 5, "label" => nil}
            ]
          }
        ],
        "paging" => %{"next" => %{"after" => "c1"}}
      })
    end)

    assert {:ok, %{results: [association], after: "c1"}} =
             Associations.list(client, "deals", 123, "companies")

    assert association.to_object_id == 456
    assert [%{category: "HUBSPOT_DEFINED", type_id: 5}] = association.association_types
  end

  test "list/5 forwards limit and after", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["limit"] == "500"
      assert conn.query_params["after"] == "c1"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert {:ok, %{results: [], after: nil}} =
             Associations.list(client, "deals", "123", "contacts", limit: 500, after: "c1")
  end

  test "propagates errors", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "no such deal"})
    end)

    assert {:error, %HubspotClient.Error{status: 404}} =
             Associations.list(client, "deals", "nope", "companies")
  end
end

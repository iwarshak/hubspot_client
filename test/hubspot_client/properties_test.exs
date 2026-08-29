defmodule HubspotClient.PropertiesTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Properties

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/3 returns property definitions with atom keys", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/properties/deals"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "name" => "dealname",
            "label" => "Deal Name",
            "type" => "string",
            "fieldType" => "text",
            "groupName" => "dealinformation"
          }
        ]
      })
    end)

    assert {:ok, [property]} = Properties.list(client, "deals")
    assert property.name == "dealname"
    assert property.field_type == "text"
    assert property.group_name == "dealinformation"
  end

  test "list/3 keeps portal-defined property names as string values", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      Req.Test.json(conn, %{"results" => [%{"name" => "custom_locum_specialty"}]})
    end)

    assert {:ok, [%{name: "custom_locum_specialty"}]} = Properties.list(client, "deals")
  end

  test "get/4 reads a single property definition", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/properties/deals/dealstage"

      Req.Test.json(conn, %{
        "name" => "dealstage",
        "options" => [%{"label" => "Won", "value" => "closedwon", "displayOrder" => 1}]
      })
    end)

    assert {:ok, %{name: "dealstage", options: [option]}} =
             Properties.get(client, "deals", "dealstage")

    assert option.value == "closedwon"
    assert option.display_order == 1
  end
end

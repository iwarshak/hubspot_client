defmodule HubspotClient.ResourcesTest do
  use ExUnit.Case, async: true

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  @resources [
    {HubspotClient.Deals, "deals"},
    {HubspotClient.Companies, "companies"},
    {HubspotClient.Contacts, "contacts"},
    {HubspotClient.Tickets, "tickets"}
  ]

  for {module, type} <- @resources do
    test "#{inspect(module)}.list/2 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}"
        Req.Test.json(conn, %{"results" => [%{"id" => "1"}]})
      end)

      assert {:ok, %{results: [%{id: "1"}]}} = unquote(module).list(client)
    end

    test "#{inspect(module)}.get/3 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}/7"
        Req.Test.json(conn, %{"id" => "7"})
      end)

      assert {:ok, %{id: "7"}} = unquote(module).get(client, "7")
    end

    test "#{inspect(module)}.search/2 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}/search"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, %{results: []}} = unquote(module).search(client, %{"limit" => 1})
    end

    test "#{inspect(module)}.batch_read/3 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}/batch/read"
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, []} = unquote(module).batch_read(client, ["1"])
    end

    test "#{inspect(module)}.stream/2 targets #{type}", %{client: client} do
      Req.Test.stub(HubspotClient, fn conn ->
        assert conn.request_path == "/crm/v3/objects/#{unquote(type)}"
        Req.Test.json(conn, %{"results" => [%{"id" => "1"}]})
      end)

      assert [%{id: "1"}] = client |> unquote(module).stream() |> Enum.to_list()
    end
  end
end

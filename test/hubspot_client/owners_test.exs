defmodule HubspotClient.OwnersTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Owners

  setup do
    client =
      HubspotClient.new(
        token: "t",
        req_options: [plug: {Req.Test, HubspotClient}, retry: false]
      )

    {:ok, client: client}
  end

  test "list/2 returns a paged envelope", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/owners"

      Req.Test.json(conn, %{
        "results" => [
          %{
            "id" => "77",
            "email" => "rep@example.com",
            "firstName" => "Alex",
            "lastName" => "Kim",
            "userId" => 991,
            "createdAt" => "2026-01-01T00:00:00Z",
            "archived" => false
          }
        ],
        "paging" => %{"next" => %{"after" => "c1"}}
      })
    end)

    assert {:ok, %{results: [owner], after: "c1"}} = Owners.list(client)
    assert owner.email == "rep@example.com"
    assert owner.first_name == "Alex"
    assert owner.user_id == 991
    assert owner.created_at == ~U[2026-01-01 00:00:00Z]
  end

  test "list/2 forwards limit, after, and archived", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["limit"] == "50"
      assert conn.query_params["after"] == "c1"
      assert conn.query_params["archived"] == "true"
      Req.Test.json(conn, %{"results" => []})
    end)

    assert {:ok, _} = Owners.list(client, limit: 50, after: "c1", archived: true)
  end

  test "get/3 reads a single owner", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      assert conn.request_path == "/crm/v3/owners/77"
      Req.Test.json(conn, %{"id" => "77", "email" => "rep@example.com"})
    end)

    assert {:ok, %{id: "77", email: "rep@example.com"}} = Owners.get(client, "77")
  end
end

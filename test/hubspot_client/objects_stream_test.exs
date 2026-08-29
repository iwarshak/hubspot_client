defmodule HubspotClient.ObjectsStreamTest do
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

  defp stub_pages(pages) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(HubspotClient, fn conn ->
      index = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
      Req.Test.json(conn, Enum.at(pages, index))
    end)

    counter
  end

  test "follows the cursor across pages and stops on a nil cursor", %{client: client} do
    stub_pages([
      %{"results" => [%{"id" => "1"}], "paging" => %{"next" => %{"after" => "c1"}}},
      %{"results" => [%{"id" => "2"}], "paging" => %{"next" => %{"after" => "c2"}}},
      %{"results" => [%{"id" => "3"}]}
    ])

    assert [%{id: "1"}, %{id: "2"}, %{id: "3"}] =
             client |> Objects.stream("deals") |> Enum.to_list()
  end

  test "sends the cursor from the previous page as the after param", %{client: client} do
    {:ok, seen} = Agent.start_link(fn -> [] end)

    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      cursor = conn.query_params["after"]
      Agent.update(seen, fn list -> list ++ [cursor] end)

      case cursor do
        nil ->
          Req.Test.json(conn, %{"results" => [], "paging" => %{"next" => %{"after" => "c1"}}})

        "c1" ->
          Req.Test.json(conn, %{"results" => []})
      end
    end)

    client |> Objects.stream("deals") |> Enum.to_list()

    assert Agent.get(seen, & &1) == [nil, "c1"]
  end

  test "defaults limit to 100 and lets the caller override it", %{client: client} do
    {:ok, seen} = Agent.start_link(fn -> [] end)

    Req.Test.stub(HubspotClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      Agent.update(seen, fn list -> list ++ [conn.query_params["limit"]] end)
      Req.Test.json(conn, %{"results" => []})
    end)

    client |> Objects.stream("deals") |> Enum.to_list()
    client |> Objects.stream("deals", limit: 25) |> Enum.to_list()

    assert Agent.get(seen, & &1) == ["100", "25"]
  end

  test "is lazy — Enum.take/2 stops requesting once satisfied", %{client: client} do
    counter =
      stub_pages(
        Enum.map(1..10, fn n ->
          %{
            "results" => [%{"id" => to_string(n)}],
            "paging" => %{"next" => %{"after" => "c#{n}"}}
          }
        end)
      )

    assert [%{id: "1"}, %{id: "2"}] = client |> Objects.stream("deals") |> Enum.take(2)
    assert Agent.get(counter, & &1) == 2
  end

  test "raises when a page request fails", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "bad token"})
    end)

    assert_raise HubspotClient.Error, ~r/bad token/, fn ->
      client |> Objects.stream("deals") |> Enum.to_list()
    end
  end

  test "raises on a transport error", %{client: client} do
    Req.Test.stub(HubspotClient, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert_raise Req.TransportError, fn ->
      client |> Objects.stream("deals") |> Enum.to_list()
    end
  end
end

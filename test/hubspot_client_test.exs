defmodule HubspotClientTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "builds a client with the given token" do
      client = HubspotClient.new(token: "pat-na1-secret")

      assert %HubspotClient{
               token: "pat-na1-secret",
               base_url: "https://api.hubapi.com",
               req_options: []
             } = client
    end

    test "allows overriding base_url and req_options" do
      client =
        HubspotClient.new(
          token: "t",
          base_url: "http://localhost:4000",
          req_options: [retry: false]
        )

      assert client.base_url == "http://localhost:4000"
      assert client.req_options == [retry: false]
    end

    test "raises when the token is missing" do
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new([]) end
    end

    test "raises when the token is not a non-empty string" do
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new(token: "") end
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new(token: nil) end
      assert_raise ArgumentError, ~r/:token/, fn -> HubspotClient.new(token: 123) end
    end
  end
end

defmodule HubspotClientTest do
  use ExUnit.Case
  doctest HubspotClient

  test "greets the world" do
    assert HubspotClient.hello() == :world
  end
end

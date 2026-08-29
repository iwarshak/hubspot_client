defmodule HubspotClient.ErrorTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Error

  describe "from_response/2" do
    test "extracts HubSpot's error fields" do
      body = %{
        "status" => "error",
        "message" => "resource not found",
        "correlationId" => "aeb5f871-1111-2222",
        "category" => "OBJECT_NOT_FOUND"
      }

      assert %Error{
               status: 404,
               category: "OBJECT_NOT_FOUND",
               message: "resource not found",
               correlation_id: "aeb5f871-1111-2222",
               body: ^body
             } = Error.from_response(404, body)
    end

    test "tolerates a map missing every known field" do
      assert %Error{status: 500, category: nil, correlation_id: nil, message: message, body: %{}} =
               Error.from_response(500, %{})

      assert is_binary(message)
    end

    test "tolerates a non-map body such as an HTML error page" do
      assert %Error{status: 502, body: "<html>bad gateway</html>", message: message} =
               Error.from_response(502, "<html>bad gateway</html>")

      assert is_binary(message)
    end
  end

  describe "Exception behaviour" do
    test "message/1 includes the status and category" do
      error = Error.from_response(429, %{"message" => "too many", "category" => "RATE_LIMIT"})
      formatted = Exception.message(error)

      assert formatted =~ "429"
      assert formatted =~ "RATE_LIMIT"
      assert formatted =~ "too many"
    end

    test "is raisable" do
      error = Error.from_response(404, %{"message" => "nope"})
      assert_raise Error, fn -> raise error end
    end
  end
end

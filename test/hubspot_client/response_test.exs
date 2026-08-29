defmodule HubspotClient.ResponseTest do
  use ExUnit.Case, async: true

  alias HubspotClient.Response

  describe "object/1" do
    test "atomizes the envelope and leaves properties string-keyed" do
      raw = %{
        "id" => "123",
        "properties" => %{"dealname" => "Acme", "amount" => "5000"},
        "createdAt" => "2026-08-29T10:00:00.000Z",
        "updatedAt" => "2026-08-29T12:00:00.000Z",
        "archived" => false
      }

      assert %{
               id: "123",
               properties: %{"dealname" => "Acme", "amount" => "5000"},
               created_at: ~U[2026-08-29 10:00:00.000Z],
               updated_at: ~U[2026-08-29 12:00:00.000Z],
               archived: false
             } = Response.object(raw)
    end

    test "defaults properties and archived when absent" do
      assert %{id: "1", properties: %{}, archived: false, created_at: nil, updated_at: nil} =
               Response.object(%{"id" => "1"})
    end

    test "passes an unparseable timestamp through unchanged" do
      assert %{created_at: "not-a-date"} = Response.object(%{"createdAt" => "not-a-date"})
    end

    test "includes associations only when present" do
      refute Map.has_key?(Response.object(%{"id" => "1"}), :associations)

      raw = %{"id" => "1", "associations" => %{"companies" => %{"results" => []}}}
      assert %{associations: %{"companies" => %{"results" => []}}} = Response.object(raw)
    end
  end

  describe "metadata/1" do
    test "converts camelCase keys to snake_case atoms, recursively" do
      raw = %{
        "id" => "default",
        "label" => "Sales Pipeline",
        "displayOrder" => 0,
        "stages" => [
          %{"id" => "1", "label" => "Appointment", "metadata" => %{"isClosed" => "false"}}
        ]
      }

      assert %{
               id: "default",
               label: "Sales Pipeline",
               display_order: 0,
               stages: [%{id: "1", label: "Appointment", metadata: %{is_closed: "false"}}]
             } = Response.metadata(raw)
    end

    test "parses created_at and updated_at but leaves other strings alone" do
      raw = %{"createdAt" => "2026-08-29T10:00:00Z", "label" => "2026-08-29T10:00:00Z"}
      decoded = Response.metadata(raw)

      assert decoded.created_at == ~U[2026-08-29 10:00:00Z]
      assert decoded.label == "2026-08-29T10:00:00Z"
    end

    test "leaves scalars and lists of scalars alone" do
      assert Response.metadata("plain") == "plain"
      assert Response.metadata(7) == 7
      assert Response.metadata(["a", "b"]) == ["a", "b"]
    end
  end

  describe "paged/2" do
    test "maps results and extracts the cursor" do
      body = %{
        "results" => [%{"id" => "1"}, %{"id" => "2"}],
        "paging" => %{"next" => %{"after" => "NTI1Cg", "link" => "https://..."}}
      }

      assert %{results: [%{id: "1"}, %{id: "2"}], after: "NTI1Cg"} =
               Response.paged(body, &Response.object/1)
    end

    test "returns a nil cursor on the last page" do
      assert %{results: [], after: nil} =
               Response.paged(%{"results" => []}, &Response.object/1)
    end
  end

  describe "collection/2" do
    test "maps results to a plain list" do
      body = %{"results" => [%{"label" => "A"}, %{"label" => "B"}]}
      assert [%{label: "A"}, %{label: "B"}] = Response.collection(body, &Response.metadata/1)
    end
  end
end

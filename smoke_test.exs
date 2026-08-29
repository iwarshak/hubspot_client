# Read-only smoke test against a real HubSpot portal.
# Run with: set -a; . ./.env; set +a; mix run smoke_test.exs
client = HubspotClient.new(token: System.fetch_env!("HUBSPOT_TOKEN"))

{:ok, pipelines} = HubspotClient.Pipelines.list(client, "deals")
IO.puts("deal pipelines: #{inspect(Enum.map(pipelines, & &1.label))}")

case pipelines do
  [%{id: id} | _] ->
    {:ok, stages} = HubspotClient.Pipelines.stages(client, "deals", id)
    IO.puts("stages in #{id}: #{inspect(Enum.map(stages, & &1.label))}")
  [] ->
    IO.puts("stages: (no pipelines to inspect)")
end

{:ok, %{results: deals, after: cursor}} =
  HubspotClient.Deals.list(client, limit: 3, properties: ["dealname", "amount", "dealstage"])

IO.puts("deals returned: #{length(deals)}, more pages: #{cursor != nil}")
Enum.each(deals, fn d -> IO.puts("  - #{inspect(d.properties["dealname"])} #{inspect(d.properties["amount"])}") end)

{:ok, props} = HubspotClient.Properties.list(client, "deals")
IO.puts("deal properties defined: #{length(props)}")

{:ok, %{results: owners}} = HubspotClient.Owners.list(client, limit: 3)
IO.puts("owners: #{inspect(Enum.map(owners, & &1.email))}")

streamed = client |> HubspotClient.Deals.stream(properties: ["dealname"]) |> Enum.take(5)
IO.puts("stream took #{length(streamed)} deals lazily")

IO.puts("\nOK — all read paths worked against the live portal.")

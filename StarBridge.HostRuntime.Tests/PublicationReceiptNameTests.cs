using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Privacy;

internal static partial class PublicationReceiptDiagnosticTests
{
    private static IEnumerable<(string Name, Func<Task> Test)> NameBoundaryCases()
    {
        yield return ("CX-RECEIPT-NAME different names rejected on all three lanes", DifferentNames);
        yield return ("CX-RECEIPT-NAME empty and nonempty names stay distinct", EmptyNames);
        yield return ("CX-RECEIPT-NAME name types and missing names stay strict", NameTypes);
        yield return ("CX-RECEIPT-NAME location case remains strict", LocationCase);
        yield return ("CX-RECEIPT-NAME every validated field has value-free diagnostics", FieldDiagnostics);
        yield return ("CX-RECEIPT-NAME journal field allowlist rejects arbitrary input", FieldAllowlist);
        yield return ("CX-RECEIPT-NAME diagnostic failures preserve validation", DiagnosticFailures);
    }

    private static async Task NameCase()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) {
                PayloadName = "Mixed_Test_Name",
                ChangeReceiptState = state => {
                    Check(state["name"]!.GetValue<string>() == "Mixed_Test_Name", "nonempty mixed-case name reaches receipt");
                    state["name"] = "mixed_test_name";
                }
            }.Start();
            await fixture.Send();
            Check(fixture.Lines().Length == 0, "case-only name receipt succeeds silently on " + lane);
        }
    }

    private static async Task DifferentNames()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) { PayloadName = "Mixed_Test_Name",
                ChangeReceiptState = state => state["name"] = "Other_Test_Name" }.Start();
            await Reject(fixture.Send);
            AssertField(fixture, "name", "Mixed_Test_Name", "Other_Test_Name");
        }
    }

    private static async Task EmptyNames()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        foreach (var (sent, received) in new[] { ("", "Mixed_Test_Name"), ("Mixed_Test_Name", "") })
        {
            using var fixture = new Fixture(lane) { PayloadName = sent,
                ChangeReceiptState = state => state["name"] = received }.Start();
            await Reject(fixture.Send);
            AssertField(fixture, "name", "Mixed_Test_Name");
        }
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) { PayloadName = "" }.Start();
            await fixture.Send();
            Check(fixture.Lines().Length == 0, "matching empty names still succeed");
        }
    }

    private static async Task NameTypes()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        foreach (var value in new[] { "null", "7", "true", "[]", "{}" })
        {
            using var fixture = new Fixture(lane) { PayloadName = "Mixed_Test_Name",
                ChangeReceiptState = state => state["name"] = JsonNode.Parse(value) }.Start();
            await Reject(fixture.Send);
            AssertField(fixture, "name", "Mixed_Test_Name");
        }
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) { PayloadName = "Mixed_Test_Name",
                ChangeReceiptState = state => state.Remove("name") }.Start();
            await Reject(fixture.Send);
            AssertField(fixture, "name", "Mixed_Test_Name");
        }
    }

    private static async Task LocationCase()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) { ChangeReceiptState = state => {
                Check(state["location"]!.GetValue<string>() == "Unknown", "location starts with mixed case");
                state["location"] = "unknown";
            } }.Start();
            await Reject(fixture.Send);
            AssertField(fixture, "location", "Unknown", "unknown");
        }
    }

    private static async Task FieldDiagnostics()
    {
        var fields = new[] { "name", "online", "ship", "location", "liveStatus", "visibilityScope",
            "roomVisibilityScope", "fleetSharedStateFields", "roomSharedStateFields", "fleetAdministratorsCanView",
            "fleetMembersCanView", "roomMembersCanView", "friendsCanViewPresence",
            "fleetVisibilityGroupIds", "roomVisibilityGroupIds", "serverShard", "serverRegion" };
        foreach (var lane in new[] { "legacy", "community", "official" })
        foreach (var field in fields)
        {
            using var fixture = new Fixture(lane) {
                ChangeReceiptState = state => state[field] = "Mismatch_Value_Only"
            }.Start();
            await Reject(fixture.Send);
            AssertField(fixture, field, "Mismatch_Value_Only");
        }
        // Missing optional server fields still match null, as before.
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) { ChangeReceiptState = state => {
                state.Remove("serverShard"); state.Remove("serverRegion");
            } }.Start();
            await fixture.Send();
            Check(fixture.Lines().Length == 0, "missing nullable server fields remain accepted");
        }
    }

    private static Task FieldAllowlist()
    {
        using var fixture = new Fixture("legacy");
        var journal = new CommunityReadJournal(fixture.Root);
        foreach (var field in new[] { "Name", "state.name", "name\nInjected_Value", "Private_Field_Value", "", null })
            journal.RecordReceipt("publication-receipt", "privacy_publication.response_invalid", 200, "json", 1, field);
        var lines = fixture.Lines();
        Check(lines.Length == 6 && lines.All(line => !line.Contains("mismatchField=")), "only exact fixed field names are allowed");
        OfficialHangarDiagnosticTests.AssertPrivate(lines, "Injected_Value", "Private_Field_Value", "state.name");
        return Task.CompletedTask;
    }

    private static async Task DiagnosticFailures()
    {
        foreach (var lane in new[] { "legacy", "community", "official" })
        {
            using var fixture = new Fixture(lane) { PayloadName = "Mixed_Test_Name",
                ChangeReceiptState = state => state["name"] = "Other_Test_Name" }.Start();
            var calls = 0;
            string? observedField = null;
            fixture.Writer.ReceiptDiagnostic = (_, _, _, _, _, field) => {
                calls++;
                observedField = field;
                throw new IOException("Observer_Failure_Value");
            };
            await Reject(fixture.Send);
            Check(calls == 1 && observedField == "name", "throwing observer receives the mismatch field once");
            fixture.ChangeReceiptState = null;
            await fixture.Send();
            Check(calls == 1, "success remains silent with throwing observer");

            Directory.CreateDirectory(fixture.Root);
            var blocked = Path.Combine(fixture.Root, "blocked");
            File.WriteAllText(blocked, "test-only-blocker");
            fixture.Writer.ReceiptDiagnostic = new CommunityReadJournal(blocked).RecordReceipt;
            fixture.ChangeReceiptState = state => state["name"] = "Other_Test_Name";
            await Reject(fixture.Send);
            Check(File.ReadAllText(blocked) == "test-only-blocker", "journal write failure preserves blocker and validation error");
        }
    }

    private static void AssertField(Fixture fixture, string field, params string[] forbidden)
    {
        AssertInvalid(fixture, "json", 200);
        var lines = fixture.Lines();
        Check(lines.Single().EndsWith(" mismatchField=" + field, StringComparison.Ordinal), "exact mismatch field is journaled");
        OfficialHangarDiagnosticTests.AssertPrivate(lines, forbidden);
    }
}

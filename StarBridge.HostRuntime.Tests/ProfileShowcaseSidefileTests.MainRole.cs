using System.Text.Json;
using StarBridge.HostRuntime.Profiles;

internal static partial class ProfileShowcaseSidefileTests
{
    // 0.7.3 main role (user 11-05): beside the main file only, so 0.7.2.1 reads exactly what it read before.
    private static void MainRole()
    {
        using var f = new Fixture();
        var roles = new LocalProfilePlayStyle(["pilot", "gunner"]);
        var first = f.Save(Content with { PlayStyle = roles, MainRole = "gunner" });
        var mainText = File.ReadAllText(f.Main);
        Check(!mainText.Contains("mainRole", StringComparison.OrdinalIgnoreCase), "main file never carries the main role");
        var old = JsonSerializer.Deserialize<OldSavedFile>(File.ReadAllBytes(f.Main), OldJson)!;
        Check(old.Integrity == OldIntegrity(old.OwnerHash, old.Snapshot), "0.7.2.1 reader accepts the main file unchanged");
        Check(File.ReadAllText(f.Side).Contains("\"mainRole\":\"gunner\""), "the sidefile holds it");
        Check(f.Store.Read(Owner).Content!.MainRole == "gunner", "read back");

        // An edit without the field keeps it; removing the role drops it; "" clears it.
        var kept = f.Save(Content with { PlayStyle = roles }, first.Revision);
        Check(kept.Content!.MainRole == "gunner" && f.Store.Read(Owner).Content!.MainRole == "gunner", "omitted keeps");
        var dropped = f.Save(Content with { PlayStyle = new LocalProfilePlayStyle(["pilot"]) }, kept.Revision);
        Check(dropped.Content!.MainRole is null && f.Store.Read(Owner).Content!.MainRole is null, "an unticked role is no main role");
        var again = f.Save(Content with { PlayStyle = roles, MainRole = "pilot" }, dropped.Revision);
        var cleared = f.Save(Content with { PlayStyle = roles, MainRole = "" }, again.Revision);
        Check(cleared.Content!.MainRole is null && f.Store.Read(Owner).Content!.MainRole is null, "\"\" clears");
        Check(!File.ReadAllText(f.Side).Contains("mainRole"), "a cleared main role leaves the earlier sidefile shape");

        // Only a ticked role, at most 80 characters, no control characters.
        foreach (var bad in new[] { "medic", new string('x', 81), "pi\nlot" })
        {
            try { f.Save(Content with { PlayStyle = roles, MainRole = bad }, cleared.Revision); throw new Exception("accepted " + bad); }
            catch (LocalProfileException e) when (e.Code == "profile_local.invalid_request") { }
        }

        // A sidefile whose main role was edited by hand fails its checksum: the page still reads, without it.
        f.Save(Content with { PlayStyle = roles, MainRole = "gunner" }, cleared.Revision);
        File.WriteAllText(f.Side, File.ReadAllText(f.Side).Replace("\"gunner\"", "\"pilot\""));
        var read = f.Store.Read(Owner);
        Check(read.Content is not null && read.Content.MainRole is null && read.Content.Showcases is null, "tampered sidefile ignored");
    }
}

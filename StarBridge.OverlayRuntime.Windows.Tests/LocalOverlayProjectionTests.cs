using System.IO;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

// Crosses the actual Host source and Native projection seams. This harness
// never constructs NativeInformationOverlayRuntime or a visible window.
internal static class LocalOverlayProjectionTests
{
    internal static void Run()
    {
        foreach (var (name, test) in new (string, Action)[] {
            ("actual local log reaches the native self display without social authority", ActualDisplay),
            ("exit clears native game fields while retaining the confirmed local identity", Stopped),
            ("missing explicit module sources stay empty in the native projection", MissingModules),
            ("retained native input is rejected after evidence and mode changes", Retained),
            ("local profile changes replace native module continuity without merging", ProfileChanges),
            ("unavailable social chat choices do not invent a local chat channel", MultiChat)
        }) { test(); Console.WriteLine("PASS local native projection: " + name); }
    }

    private static void ActualDisplay()
    {
        using var f = new LocalOverlaySourceTests.Fixture(); f.Enable();
        var frame = f.Source.Capture()!; var hash = f.Hash();
        foreach (var language in new[] { "en", "zh", "zh-Hant" })
        {
            var result = NativeInformationOverlayRuntime.ProjectLocalOwned(frame.Read(), language);
            var row = result.Scene.Players.Single();
            Check(result.Scene.HasContent && row.IsSelf && row.Name == "Pilot-Example" && row.SharedPresence == PlayerPresenceKind.InGame,
                "The confirmed local Handle is its own display row, not a remote roster member.");
            var ship = frame.Read().Session.Ship;
            var expectedShip = (language.StartsWith("zh") ? ship.ChineseName : ship.EnglishName) ?? ship.EnglishName ?? ship.Key;
            Check(row.ServerShard == "pub_sc_alpha_apse1_123" && row.Ship == expectedShip,
                "The actual local parser's current server and ship reach Native projection.");
            Check(row.AccountId is null && !row.ShowMemberActions && result.Scene.Context is { IsLocalOnly: true, RoomId: null, ChatChannelId: null } &&
                result.Chat.Length == 0 && string.IsNullOrEmpty(result.Command.NoticeText),
                "No account actions, social room, chat or announcement authority is created.");
        }
        var modules = Project(frame);
        Check(modules.Overview.Scene.Players.Single().IsSelf && modules.Members.Scene.Players.Single().AccountId is null &&
            modules.Notice.Scene.Players.Count == 0 && modules.Chat.Chat.Count == 0,
            "The existing module renderer accepts the same actual local source without a fake account.");
        Check(hash.SequenceEqual(f.Hash()), "Projection never modifies local identity settings.");
    }

    private static void Stopped()
    {
        using var f = new LocalOverlaySourceTests.Fixture(); f.Enable();
        f.Process = new("notRunning"); f.Game.Sample();
        var result = NativeInformationOverlayRuntime.ProjectLocalOwned(f.Source.Capture()!.Read(), "en");
        var row = result.Scene.Players.Single();
        Check(row.Name == "Pilot-Example" && row.SharedPresence == PlayerPresenceKind.AppOnline &&
            row.ServerShard is null && row.ServerRegion is null && row.SharedHasServerSession == false &&
            row.SharedShipText?.Contains("Arrow", StringComparison.OrdinalIgnoreCase) != true,
            "A confirmed game exit cannot display the last ship, server or in-game presence.");
        f.Game.ApplyListening(f.Key, false);
        Check(NativeInformationOverlayRuntime.ProjectLocalOwned(f.Source.Capture()!.Read(), "en").Scene.Players.Count == 0,
            "Stopped listening cannot keep a named current game row.");
    }

    private static void MissingModules()
    {
        using var f = new LocalOverlaySourceTests.Fixture(); f.Enable();
        var preset = new OverlayPresetSources(OverlaySourceBinding.Automatic,
            modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding> {
                [OverlaySourceModule.Members] = new(OverlaySourceMode.Community, "synthetic-org", "synthetic-owner"),
                [OverlaySourceModule.Chat] = new(OverlaySourceMode.Room)
            });
        var frame = f.Source.Capture()!;
        var modules = Project(frame, LocalOverlaySourceTests.Workspace(preset));
        Check(modules.Overview.Available && modules.Overview.Scene.Players.Single().IsSelf &&
            !modules.Members.Available && modules.Members.Scene.Players.Count == 0 &&
            !modules.Chat.Available && modules.Chat.Chat.Count == 0,
            "A local overview never replaces a selected but unavailable organization or room module.");
        var hidden = Project(frame, LocalOverlaySourceTests.Workspace() with {
            Settings = LocalOverlaySourceTests.Workspace().Settings with { ShowMembers = false }
        });
        Check(!hidden.Members.Available && hidden.Members.Scene.Players.Count == 0 && hidden.Members.EmptyMessage is null,
            "An explicitly hidden module is not reopened as a local default or an error panel.");
    }

    private static void Retained()
    {
        using var f = new LocalOverlaySourceTests.Fixture(); f.Enable();
        var frame = f.Source.Capture()!; var moduleFrame = frame.ReadModules(LocalOverlaySourceTests.Workspace()).Frame!;
        var oldObservation = frame.Read();
        File.AppendAllText(f.Log, "incomplete identity="); f.Game.Sample();
        Check(NativeInformationOverlayRuntime.ProjectLocalOwned(frame.Read(), "en").Scene.Players.Count == 0,
            "Current display-time reads reject retained local evidence after uncertainty.");
        var modules = NativeInformationOverlayRuntime.ProjectModules(moduleFrame, "en", f.Clock.Now, localDisplay: oldObservation);
        Check(!modules.Members.Available && modules.Members.Scene.Players.Count == 0 && modules.Overview.Scene.Players.Count == 0,
            "Even a retained observation cannot override the actual module frame's revoked authority.");
        f.Write(); f.Game.Sample(); frame = f.Source.Capture()!;
        f.Mode = (false, 2);
        Check(NativeInformationOverlayRuntime.ProjectLocalOwned(frame.Read(), "en").Scene.Players.Count == 0,
            "Changing mode cannot reuse an old local identity row.");
    }

    private static void ProfileChanges()
    {
        using var f = new LocalOverlaySourceTests.Fixture(); f.Enable();
        var frame = f.Source.Capture()!; var first = Project(frame);
        f.Write("Other-Pilot", "200"); f.Game.Sample();
        Check(NativeInformationOverlayRuntime.ProjectLocalOwned(frame.Read(), "en").Scene.Players.Count == 0,
            "A new unconfirmed Handle removes the previous Native self row.");
        f.Confirm(); f.Game.Sample(); var second = Project(f.Source.Capture()!);
        Check(second.Members.Scene.Players.Single().Name == "Other-Pilot" && first.ScopeKey != second.ScopeKey &&
            second.Members.Scene.Players.Single().AccountId is null && f.Identities.Read().Profiles.Count == 2,
            "Explicit profile selection changes Native continuity, not account data ownership.");
        f.Write(); f.Game.Sample(); f.Confirm(); f.Game.Sample(); var third = Project(f.Source.Capture()!);
        Check(third.ScopeKey != first.ScopeKey && third.Members.Scene.Players.Single().Name == "Pilot-Example",
            "Returning to the same Handle cannot resurrect a retained old Native module batch.");
    }

    private static void MultiChat()
    {
        using var f = new LocalOverlaySourceTests.Fixture(); f.Enable();
        var preset = new OverlayPresetSources(OverlaySourceBinding.Automatic,
            chatSources: [new(OverlaySourceMode.Room), new(OverlaySourceMode.Community, "synthetic-org", "synthetic-owner")]);
        var projection = Project(f.Source.Capture()!, LocalOverlaySourceTests.Workspace(preset));
        Check(!projection.Chat.Available && projection.Chat.Chat.Count == 0 && projection.Chat.Scene.Context is
            { IsLocalOnly: true, RoomId: null, ChatChannelId: null },
            "Unavailable social choices cannot create a multi-chat channel in local mode.");
    }

    private static OverlayModulePresentation Project(InformationOverlayLocalSourceFrame frame,
        InformationOverlayRuntimeWorkspace? workspace = null) =>
        NativeInformationOverlayRuntime.ProjectModules(frame.ReadModules(workspace ?? LocalOverlaySourceTests.Workspace()).Frame!,
            "en", LocalOverlaySourceTests.Start, localDisplay: frame.Read());
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}

using System.Text.RegularExpressions;

// Source inventory is deliberately closed: adding a read requires reviewing its
// observation/persistence path and adding a behavioral case, not just an out var.
internal static partial class SharingReviewRegressionTests
{
    private static Task VisibilityReadArchitecture()
    {
        VerifyVisibilitySourceLayouts();
        var sourceRoot = FindVisibilitySourceRoot(AppContext.BaseDirectory);
        var sources = Directory.EnumerateFiles(sourceRoot, "*.cs", SearchOption.AllDirectories)
            .Where(p => !Path.GetRelativePath(sourceRoot, p).Split(Path.DirectorySeparatorChar).Any(s => s is "obj" or "bin"))
            .ToDictionary(p => Path.GetRelativePath(sourceRoot, p).Replace('\\', '/'), File.ReadAllText);
        VerifyVisibilitySources(sources);
        var raw = typeof(StarBridge.HostRuntime.Account.ScmAccountBridgeHost).GetProperty("RealtimePresenceStatus",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
        Check(raw?.GetMethod?.IsPrivate == true, "raw realtime status must not be accessible outside its owner");
        var provider = typeof(StarBridge.HostRuntime.Privacy.PrivacyPublication).GetField("_visibilitySnapshot",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
        Check(provider is { IsPrivate: true, IsInitOnly: true }, "raw snapshot delegate must remain private and readonly");
        foreach (var (file, from, to) in new[] {
            ("Privacy/PrivacyPublication.Visibility.cs", "var snapshot = ReadVisibility(input);", "var snapshot = _visibilitySnapshot();"),
            ("Privacy/PrivacyPublication.cs", "out var failureVisibility", "out _"),
            ("Privacy/PrivacyPublication.cs", "var snapshot = _visibilitySnapshot();", "_ = _visibilitySnapshot();"),
            ("Privacy/PrivacyPublication.cs", "ObserveVisibility(snapshot);", "// discarded snapshot"),
            ("Settings/PresenceVisibilityBridge.cs", "observeVisibility?.Invoke(snapshot, wakePublication);", "// discarded snapshot"),
            ("Privacy/PrivacyPublication.cs", "var snapshot = _visibilitySnapshot();", "var snapshot = _visibilitySnapshot(); _ = _visibilitySnapshot.Invoke();"),
            ("Privacy/PrivacyPublication.cs", "var snapshot = _visibilitySnapshot();", "var snapshot = _visibilitySnapshot(); _visibilitySnapshot();"),
            ("Privacy/PrivacyPublication.cs", "var snapshot = _visibilitySnapshot();", "var snapshot = _visibilitySnapshot(); _ = _visibilitySnapshot?.Invoke();"),
            ("Settings/PresenceVisibilityBridge.cs", "var observed = realtimeStatus?.Invoke();", "var observed = realtimeStatus?.Invoke(); realtimeStatus();"),
            ("Settings/PresenceVisibilityBridge.cs", "var observed = realtimeStatus?.Invoke();", "var observed = realtimeStatus?.Invoke(); _ = realtimeStatus.Invoke();"),
            ("Account/ScmAccountBridgeHost.Privacy.cs", "var snapshot = ReadObservedPublicationVisibility();", "var snapshot = ReadObservedPublicationVisibility(); _ = RealtimePresenceStatus;"),
            ("AccountBridgeRuntime.cs", "var snapshot = _presenceVisibility?.ReadPublicationSnapshot();", "var snapshot = _presenceVisibility?.ReadPublicationSnapshot(); _ = appScm.RealtimePresenceStatus;"),
        }) {
            Check(sources[file].Contains(from), "mutation anchor must exist: " + from);
            var mutated = new Dictionary<string, string>(sources) { [file] = sources[file].Replace(from, to) };
            var rejected = false;
            try { VerifyVisibilitySources(mutated); } catch { rejected = true; }
            Check(rejected, "source guard must reject mutation: " + from);
        }
        return Task.CompletedTask;
    }

    private static string FindVisibilitySourceRoot(string start)
    {
        for (var root = new DirectoryInfo(start); root is not null; root = root.Parent)
        {
            var candidate = Path.Combine(root.FullName, "StarBridge.HostRuntime");
            // Artifact layouts also contain a directory named after the project.
            // Require actual source, not a bin/obj/package directory of that name.
            if (File.Exists(Path.Combine(candidate, "StarBridge.HostRuntime.csproj")) &&
                File.Exists(Path.Combine(candidate, "Privacy", "PrivacyPublication.cs"))) return candidate;
        }
        throw new InvalidOperationException("source root is required for visibility architecture regression: " + start);
    }

    private static void VerifyVisibilitySourceLayouts()
    {
        var root = Directory.CreateTempSubdirectory("visibility-source-layout-").FullName;
        try
        {
            var source = Path.Combine(root, "StarBridge.HostRuntime");
            Directory.CreateDirectory(Path.Combine(source, "Privacy"));
            File.WriteAllText(Path.Combine(source, "StarBridge.HostRuntime.csproj"), "<Project />");
            File.WriteAllText(Path.Combine(source, "Privacy", "PrivacyPublication.cs"), "// fixture");
            foreach (var layout in new[] { "StarBridge.HostRuntime.Tests/bin/Release/net8.0", "_cxbuild/artifacts/bin/StarBridge.HostRuntime.Tests/release", "slice/tests/bin" })
            {
                var start = Directory.CreateDirectory(Path.Combine(root, layout)).FullName;
                Directory.CreateDirectory(Path.Combine(Directory.GetParent(start)!.FullName, "StarBridge.HostRuntime"));
                Check(FindVisibilitySourceRoot(start) == source, "source discovery ignores artifact siblings: " + layout);
            }
            try { FindVisibilitySourceRoot(Path.GetPathRoot(root)!); }
            catch (InvalidOperationException) { return; }
            throw new Exception("missing source must fail closed");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void VerifyVisibilitySources(Dictionary<string, string> sources)
    {
        var expected = new Dictionary<string, string[]> {
            ["AccountBridgeRuntime.cs"] = [
                "visibilitySnapshot: visibility is null ? null : () => _presenceVisibility!.ReadPublicationSnapshot(wakePublication: false),",
                "var snapshot = _presenceVisibility?.ReadPublicationSnapshot();"
            ],
            ["Account/ScmAccountBridgeHost.Privacy.cs"] = [
                "!HasObservedAppPresence(input))",
                "internal bool HasObservedAppPresence(PrivacyPublicationInput input)",
                "var snapshot = ReadObservedPublicationVisibility();"
            ],
            ["Account/ScmAccountBridgeHost.Realtime.cs"] = [
                "private int? RealtimePresenceStatus",
                "=> _publicationVisibility = create(() => RealtimePresenceStatus);",
                "internal PublicationVisibilitySnapshot? ReadObservedPublicationVisibility(bool wakePublication = true)",
                "=> _publicationVisibility?.ReadPublicationSnapshot(wakePublication: wakePublication);",
                "changed = ReadObservedPublicationVisibility(wakePublication: false)?.Observation != status;",
                "_ = ReadObservedPublicationVisibility(wakePublication: false);"
            ],
            ["Account/ScmAccountBridgeHost.RoomAvatarTargets.cs"] = [
                "return member with { PresenceText = ReadObservedPublicationVisibility()?.Observation switch {"
            ],
            ["Privacy/PrivacyPublication.cs"] = [
                "var choiceVisibility = ReadVisibility(input);",
                "var visibility = ReadVisibility(observed);",
                "snapshot ??= ReadVisibility(input);",
                "if (!CanRetainHeartbeat(input, saved.Revision, visibility, out var admissionVisibility))",
                "retainHeartbeat = CanRetainHeartbeat(input, saved.Revision, sentVisibility, out var failureVisibility);",
                "private Settings.PublicationVisibilitySnapshot ReadVisibility(PrivacyPublicationInput? input)",
                "var snapshot = _visibilitySnapshot();",
                "private bool CanRetainHeartbeat(PrivacyPublicationInput input, long revision, PlayerPresenceVisibilityMode visibility,",
                "snapshot = ReadVisibility(input);",
                "var snapshot = ReadVisibility(input);"
            ],
            ["Privacy/PrivacyPublication.Visibility.cs"] = [
                "var snapshot = ReadVisibility(input);",
                "var snapshot = ReadVisibility(input);"
            ],
            ["Settings/PresenceVisibilityBridge.cs"] = [
                "var snapshot = ReadPublicationSnapshot(wakePublication: false, captureForPublication: false);",
                "public PlayerPresenceVisibilityMode PublicationMode => ReadPublicationSnapshot().Mode;",
                "internal PublicationVisibilitySnapshot ReadPublicationSnapshot(bool wakePublication = true, bool captureForPublication = true)",
                "var observed = realtimeStatus?.Invoke();",
                "var snapshot = ReadPublicationSnapshot();"
            ]
        };
        const string readPattern = @"\b(ReadVisibility|ReadPublicationSnapshot|CanRetainHeartbeat|ReadObservedPublicationVisibility|HasObservedAppPresence)\s*\(|_visibilitySnapshot\s*(\??\.Invoke)?\s*\(|realtimeStatus\s*(\??\.Invoke)?\s*\(|\bRealtimePresenceStatus\b";
        foreach (var (file, text) in sources) {
            var reads = text.Split('\n').Select(l => l.Trim()).Where(l => Regex.IsMatch(l, readPattern)).ToArray();
            if (reads.Length == 0 && !expected.ContainsKey(file)) continue;
            Check(expected.TryGetValue(file, out var approved) && reads.SequenceEqual(approved!),
                "unreviewed/discarded visibility read in " + file);
        }
        var publication = sources["Privacy/PrivacyPublication.cs"];
        Check(Regex.IsMatch(publication, @"var snapshot = _visibilitySnapshot\(\);\s*ObserveVisibility\(snapshot\);"),
            "raw publication snapshot must immediately enter the observer");
        Check(!Regex.IsMatch(publication, @"CanRetainHeartbeat\([^;{}]*out\s+_\s*\)", RegexOptions.Singleline),
            "heartbeat visibility must never be discarded");
        Check(Regex.IsMatch(sources["Settings/PresenceVisibilityBridge.cs"],
            @"observeVisibility\?\.Invoke\(snapshot, wakePublication\);\s*return snapshot;"),
            "all bridge results must notify before projecting mode/observation");
        Check(sources["AccountBridgeRuntime.cs"].Contains("observeVisibility: _privacyPublication.ObserveVisibility"),
            "production bridge must wire the durable visibility observer");
        var writers = sources.Where(p => Path.GetFileName(p.Key).StartsWith("PrivacyRelayWriter", StringComparison.Ordinal))
            .Select(p => p.Value).ToArray();
        Check(writers.Sum(t => Regex.Matches(t, @"SendAdmittedAsync\(").Count) == 5,
            "writer admission inventory changed; cover every new positive route");
        Check(writers.Sum(t => Regex.Matches(t, @"current\?\.Invoke\(\)").Count) == 2,
            "writer callback inventory changed; cover final admission and official receipt recheck");
    }
}

using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;

internal static class FirstUseMissingModeTests
{
    internal static async Task Run()
    {
        await MissingState();
        await MissingTree();
        await EmptyOrLockOnly();
        await PresenceOnly();
        await OriginalFailedWrite();
        await UnexpectedResidue();
        await ObservedCommitRevokesEmptyOrigin();
    }

    private static async Task MissingState()
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        var store = new FirstUseModeStore(fixture.Root);
        store.Save(0, Guid.NewGuid().ToString("N"), "localPending", () => true);
        var state = Path.Combine(fixture.Root, "first-use-mode-v1", "state.bin");
        var original = File.ReadAllBytes(state);
        var kept = state + ".fixture-kept";
        File.Move(state, kept); // Test-owned root only; preserve the exact original.
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(fixture.Root,
            _ => throw new InvalidOperationException("Missing original mode must not construct online owners."));
        if (cold.FirstUseMode!.Current.State != "unavailable" || cold.FirstUseMode.LocalMode().Active ||
            cold.DeviceNetwork.Enter(default) is not null || File.Exists(state) ||
            !File.ReadAllBytes(kept).SequenceEqual(original))
            throw new InvalidOperationException("Missing original mode must remain unknown, with original bytes untouched.");
        fixture.RequireLocalStateUnchanged();
        Console.WriteLine("PASS missing original mode: no online startup, no local adoption and retained original bytes");
    }

    private static async Task MissingTree()
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        new FirstUseModeStore(fixture.Root).Save(0, Guid.NewGuid().ToString("N"), "localPending", () => true);
        var directory = Path.Combine(fixture.Root, "first-use-mode-v1");
        var original = File.ReadAllBytes(Path.Combine(directory, "state.bin"));
        var kept = directory + ".fixture-kept";
        Directory.Move(directory, kept); // Exact test-owned directory, no deletion.
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(fixture.Root,
            _ => throw new InvalidOperationException("Lost original mode tree must not construct online owners."));
        if (cold.FirstUseMode!.Current.State != "unavailable" || cold.FirstUseMode.LocalMode().Active ||
            Directory.Exists(directory) || !File.ReadAllBytes(Path.Combine(kept, "state.bin")).SequenceEqual(original))
            throw new InvalidOperationException("A lost original mode tree must remain unknown.");
        fixture.RequireLocalStateUnchanged();
        Console.WriteLine("PASS lost original mode tree: no online startup and retained original tree");
    }

    private static async Task EmptyOrLockOnly()
    {
        foreach (var residue in new[] { "empty", "state.bin.lock", "unknown.bin" })
        {
            using var fixture = new LocalAccountStopTests.Fixture();
            var directory = Path.Combine(fixture.Root, "first-use-mode-v1");
            Directory.CreateDirectory(directory);
            if (residue != "empty") File.WriteAllBytes(Path.Combine(directory, residue), [7, 8, 9]);
            using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(fixture.Root,
                _ => throw new InvalidOperationException("Residual directory must not construct online owners."));
            if (cold.FirstUseMode!.Current.State != "unavailable" || cold.FirstUseMode.LocalMode().Active ||
                File.Exists(Path.Combine(directory, "state.bin")) ||
                residue != "empty" && !File.ReadAllBytes(Path.Combine(directory, residue)).SequenceEqual(new byte[] { 7, 8, 9 }))
                throw new InvalidOperationException("Unknown residual files must remain intact and unadopted.");
            fixture.RequireLocalStateUnchanged();
        }
        Console.WriteLine("PASS missing mode: empty, lock-only and unknown residual trees are not initial state");
    }

    private static async Task PresenceOnly()
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        var marker = Path.Combine(fixture.Root, "first-use-mode-present.v1.bin");
        var opaque = new byte[] { 91, 92, 93 }; File.WriteAllBytes(marker, opaque);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(fixture.Root,
            _ => throw new InvalidOperationException("A marker supplies no online authority."));
        var store = new FirstUseModeStore(fixture.Root);
        ExpectReadFailure(() => store.Save(0, Guid.NewGuid().ToString("N"), "localPending", () => true));
        if (cold.FirstUseMode!.Current.State != "unavailable" || cold.FirstUseMode.LocalMode().Active ||
            !File.ReadAllBytes(marker).SequenceEqual(opaque) || Directory.Exists(Path.Combine(fixture.Root, "first-use-mode-v1")))
            throw new InvalidOperationException("The marker must block, not authorize or be replaced with defaults.");
        fixture.RequireLocalStateUnchanged();
        Console.WriteLine("PASS missing mode: even opaque presence evidence is negative only and remains unchanged");
    }

    private static async Task OriginalFailedWrite()
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        var store = new FirstUseModeStore(fixture.Root);
        if (store.ReadForInitialization() != FirstUseModeChoice.Unchosen)
            throw new InvalidOperationException("A genuinely untouched tree must preserve original startup.");
        var checks = 0;
        try { store.Save(0, Guid.NewGuid().ToString("N"), "localPending", () => ++checks < 2); }
        catch (LocalFirstUseException error) when (error.Code == "firstUse.context_changed") { }
        if (!File.Exists(Path.Combine(fixture.Root, "first-use-mode-present.v1.bin")) || store.Read() != FirstUseModeChoice.Unchosen)
            throw new InvalidOperationException("The original memory receipt must survive its own uncommitted write.");
        ExpectReadFailure(() => new FirstUseModeStore(fixture.Root).Read());
        using (var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(fixture.Root,
            _ => throw new InvalidOperationException("A cold reader cannot borrow the original writer's empty-state receipt.")))
            if (cold.FirstUseMode!.Current.State != "unavailable") throw new InvalidOperationException("Cold failed-write residue must remain unknown.");
        if (store.Save(0, Guid.NewGuid().ToString("N"), "localPending", () => true).Revision != 1)
            throw new InvalidOperationException("The original writer must retain the safe retry.");
        fixture.RequireLocalStateUnchanged();
        Console.WriteLine("PASS missing mode: interrupted first write remains retryable only for its actual original owner");
    }

    private static Task UnexpectedResidue()
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        var store = new FirstUseModeStore(fixture.Root); _ = store.ReadForInitialization();
        var directory = Path.Combine(fixture.Root, "first-use-mode-v1"); Directory.CreateDirectory(directory);
        var unknown = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".tmp"); File.WriteAllBytes(unknown, [11, 12]);
        ExpectReadFailure(() => store.Read());
        ExpectReadFailure(() => store.Save(0, Guid.NewGuid().ToString("N"), "localPending", () => true));
        if (!File.ReadAllBytes(unknown).SequenceEqual(new byte[] { 11, 12 }) || File.Exists(Path.Combine(directory, "state.bin")))
            throw new InvalidOperationException("Another temporary file is never an owned initial-state receipt.");
        fixture.RequireLocalStateUnchanged();
        Console.WriteLine("PASS missing mode: another temporary file invalidates even an original unwritten owner");
        return Task.CompletedTask;
    }

    private static Task ObservedCommitRevokesEmptyOrigin()
    {
        using var fixture = new LocalAccountStopTests.Fixture();
        var original = new FirstUseModeStore(fixture.Root); _ = original.ReadForInitialization();
        new FirstUseModeStore(fixture.Root).Save(0, Guid.NewGuid().ToString("N"), "localPending", () => true);
        _ = original.Read(); // Seeing any durable intent ends the empty-state receipt.
        var path = Path.Combine(fixture.Root, "first-use-mode-v1", "state.bin");
        var bytes = File.ReadAllBytes(path); File.Move(path, path + ".fixture-kept");
        ExpectReadFailure(() => original.Read());
        if (!File.ReadAllBytes(path + ".fixture-kept").SequenceEqual(bytes))
            throw new InvalidOperationException("The original durable intent must remain untouched.");
        fixture.RequireLocalStateUnchanged();
        Console.WriteLine("PASS missing mode: observing a committed intent permanently retires original empty-state permission");
        return Task.CompletedTask;
    }

    private static void ExpectReadFailure(Action action)
    {
        try { action(); }
        catch (LocalFirstUseException error) when (error.Code == "firstUse.mode_read_failed") { return; }
        throw new InvalidOperationException("Expected strict unknown original-mode state.");
    }
}

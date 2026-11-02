using StarBridge.HostRuntime.Overlay;
using System.Windows.Threading;

namespace StarBridge.Desktop;

public sealed partial class NativeInformationOverlayRuntime : ISafeHotkeyRuntime
{
    private readonly SafeHotkeyRoutes _hotkeyRoutes = new();
    private RegisteredHotkeySet? _registeredHotkeys;
    private volatile string? _registrationFailures;
    private RegisteredHotkeySet RegisteredHotkeys => _registeredHotkeys ??= new(
        (id, binding) => _messageWindow is { } window &&
            RegisterHotKey(window.Handle, id, binding.Modifiers | ModNoRepeat, binding.VirtualKey),
        id => { if (_messageWindow is { } window) _ = UnregisterHotKey(window.Handle, id); });

    public string? HotkeyRegistrationFailures => _registrationFailures;

    private void SyncRegisteredHotkeys(IReadOnlyList<GameCompatibleHotkeyRoute> wanted)
    {
        RegisteredHotkeys.Sync(wanted);
        _registrationFailures = RegisteredHotkeys.FailedText;
        if (_registrationFailures is not null)
            DesktopRuntimeDiagnostics.WriteDiagnosticLog("native-hotkey-registration-failed | fallback=raw-input");
    }
    private SortedDictionary<int, GameCompatibleHotkeyRoute> _temporaryHotkeys => _hotkeyRoutes.Menu;
    public event Action<int, long>? HostHotkeyTriggered;

    public async ValueTask ConfigureHostHotkeyAsync(int commandId, string? binding, long lease,
        CancellationToken cancellationToken = default)
    {
        var dispatcher = _dispatcher ?? throw new InvalidOperationException("Hotkey runtime unavailable.");
        await dispatcher.InvokeAsync(() =>
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var menu = _menuHotkey;
            var plan = OverlayHotkeyBindingPolicy.Build(_workspace?.HotkeyBinding ?? "Alt+O", InformationHotkeyEnabled,
                menu?.Binding, menu is { Enabled: true } && menu.IsCurrent());
            _hotkeyRoutes.ConfigureHost(commandId, binding, lease, plan.CreateGameCompatibleRoutes(0, MenuHotkeyCommand));
            _hotkeyPlan = null;
            ConfigureHotkey(_workspace?.HotkeyBinding ?? "Alt+O", InformationHotkeyEnabled);
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }

    private void TriggerTemporaryHotkey(int command) => _hotkeyRoutes.Trigger(command,
        (id, lease) => HostHotkeyTriggered?.Invoke(id, lease), id =>
        {
            if (_menuHotkey is { } owner && owner.IsCurrent()) owner.Trigger(new("command", 0, 0, 0, id));
        });

    public async ValueTask ConfigureTemporaryHotkeyAsync(int commandId, string? binding,
        CancellationToken cancellationToken = default)
    {
        if (commandId is < 2 or > 99) throw new ArgumentOutOfRangeException(nameof(commandId));
        var dispatcher = _dispatcher ?? throw new InvalidOperationException("Hotkey runtime unavailable.");
        await dispatcher.InvokeAsync(() =>
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_menuHotkey?.IsCurrent() != true) throw new InvalidOperationException("Hotkey session unavailable.");
            if (binding is null) _temporaryHotkeys.Remove(commandId);
            else
            {
                if (_temporaryHotkeys.Count >= 32 && !_temporaryHotkeys.ContainsKey(commandId))
                    throw new InvalidOperationException("Temporary hotkey limit reached.");
                var plan = OverlayHotkeyBindingPolicy.Build(binding, true, null, false);
                if (plan.InformationState != OverlayHotkeyBindingState.Ready || plan.InformationHotkey is not { } chord)
                    throw new ArgumentException("Invalid temporary hotkey.", nameof(binding));
                if (_hotkeyRoutes.Host.Values.Any(r => r.Binding == chord.ToGameCompatibleBinding()))
                    throw new InvalidOperationException("Temporary hotkey conflicts with Host route.");
                _temporaryHotkeys[commandId] = new(commandId, new(chord.VirtualKey, chord.Modifiers));
            }
            _hotkeyPlan = null;
            ConfigureHotkey(_workspace?.HotkeyBinding ?? "Alt+O", InformationHotkeyEnabled);
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }
}

// Raw Input reads every shortcut and leaves the key alone. Registering chords with
// Windows is an off-by-default user choice; Raw Input keeps running beside it.
internal static class InformationHotkeyChannel
{
    internal static string State(bool useRegistered, bool registered, bool rawReady, bool conflict) =>
        !useRegistered ? rawReady ? "registered" : "failed"
        : (registered, rawReady) switch
        {
            (true, true) => "registered",
            (false, true) => "registered",
            (true, false) => "desktopOnly",
            (false, false) when conflict => "conflict",
            _ => "failed"
        };
}

// Owned by the control dispatcher. Holds exactly the wanted chords: empty while the
// choice is off, and a chord leaves as soon as its route does (a rally ending, a menu
// session ending). A chord another program holds stays on Raw Input and is retried.
internal sealed class RegisteredHotkeySet(
    Func<int, GameCompatibleHotkeyBinding, bool> register, Action<int> unregister)
{
    private const int FirstId = 0x5B40, LastId = 0xBFFF;
    private const long PressWindowMilliseconds = 180;
    private readonly Dictionary<GameCompatibleHotkeyBinding, (int Id, int Command)> _held = [];
    private readonly Dictionary<int, uint> _lastPress = [];
    private Dictionary<GameCompatibleHotkeyBinding, int> _failed = [];
    private int _nextId = FirstId;

    internal IReadOnlyCollection<GameCompatibleHotkeyBinding> Failed => _failed.Keys;
    internal string? FailedText => _failed.Count == 0 ? null :
        string.Join(", ", _failed.Keys.Select(Describe).Order(StringComparer.Ordinal));

    internal void Sync(IReadOnlyList<GameCompatibleHotkeyRoute> wanted)
    {
        var next = new Dictionary<GameCompatibleHotkeyBinding, int>();
        foreach (var route in wanted) next.TryAdd(route.Binding, route.CommandId);
        // A chord that changes command gets a new id too: a press already queued under
        // the old id must end with the old route, never reach the new one.
        foreach (var (binding, held) in _held.ToArray())
        {
            if (next.TryGetValue(binding, out var command) && command == held.Command) continue;
            unregister(held.Id);
            _held.Remove(binding);
        }
        _failed = [];
        foreach (var (binding, command) in next)
            if (!_held.ContainsKey(binding) && !TryRegister(binding, command)) _failed[binding] = command;
        foreach (var gone in _lastPress.Keys.Where(command => !next.ContainsValue(command)).ToArray()) _lastPress.Remove(gone);
    }

    internal bool RetryFailed()
    {
        var any = false;
        foreach (var (binding, command) in _failed.ToArray())
            if (TryRegister(binding, command)) { _failed.Remove(binding); any = true; }
        return any;
    }

    internal bool Holds(int command) => _held.Values.Any(held => held.Command == command);

    internal bool TryResolve(int id, out int command)
    {
        foreach (var held in _held.Values)
            if (held.Id == id) { command = held.Command; return true; }
        command = 0;
        return false;
    }

    // Message time, which wraps every 49.7 days.
    internal bool AcceptPress(int command, uint timestamp)
    {
        // Either channel can arrive first, so the window runs in both directions.
        if (_lastPress.TryGetValue(command, out var last) &&
            Math.Min(unchecked(timestamp - last), unchecked(last - timestamp)) <= PressWindowMilliseconds)
            return false;
        _lastPress[command] = timestamp;
        return true;
    }

    private bool TryRegister(GameCompatibleHotkeyBinding binding, int command)
    {
        var id = _nextId;
        while (_held.Values.Any(held => held.Id == id)) id = id >= LastId ? FirstId : id + 1;
        // Ids are not reused at once, for the same reason a changed chord gets a new one.
        _nextId = id >= LastId ? FirstId : id + 1;
        if (!register(id, binding)) return false;
        _held[binding] = (id, command);
        return true;
    }

    internal static string Describe(GameCompatibleHotkeyBinding binding)
    {
        var parts = new List<string>();
        if ((binding.Modifiers & GameCompatibleHotkeyModifiers.Control) != 0) parts.Add("Ctrl");
        if ((binding.Modifiers & GameCompatibleHotkeyModifiers.Alt) != 0) parts.Add("Alt");
        if ((binding.Modifiers & GameCompatibleHotkeyModifiers.Shift) != 0) parts.Add("Shift");
        if ((binding.Modifiers & GameCompatibleHotkeyModifiers.Windows) != 0) parts.Add("Win");
        var key = binding.VirtualKey;
        parts.Add(key is >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A ? ((char)key).ToString()
            : key is >= 0x70 and <= 0x87 ? "F" + (key - 0x6F) : "0x" + key.ToString("X2"));
        return string.Join("+", parts);
    }
}

// Owned by the control dispatcher. Host callbacks run on the pool, never on it.
internal sealed class SafeHotkeyRoutes
{
    private static int _lastHostCommand = 999;
    private readonly Dictionary<int, HostRoute> _hostCommands = new();
    // Tests replace this so a run never writes to the user's real diagnostics log.
    internal Action<string> Diagnostic { get; init; } = DesktopRuntimeDiagnostics.WriteDiagnosticLog;
    internal SortedDictionary<int, GameCompatibleHotkeyRoute> Menu { get; } = new();
    internal sealed record HostRoute(int Slot, int CommandId, GameCompatibleHotkeyBinding Binding, long Lease);
    internal SortedDictionary<int, HostRoute> Host { get; } = new();

    // Never wrap or recycle: an old command can still be queued in a native window.
    // Static allocation also protects replacement runtime instances in this process.
    internal static int AllocateHostCommand(ref int lastCommand)
    {
        while (true)
        {
            var previous = Volatile.Read(ref lastCommand);
            if (previous == int.MaxValue) throw new InvalidOperationException("Host hotkey command IDs exhausted.");
            var next = previous + 1;
            if (Interlocked.CompareExchange(ref lastCommand, next, previous) == previous) return next;
        }
    }

    internal void ConfigureHost(int slot, string? binding, long lease, IEnumerable<GameCompatibleHotkeyRoute> primary)
    {
        if (slot is not (100 or 101)) throw new ArgumentOutOfRangeException(nameof(slot));
        if (binding is null)
        {
            if (Host.Remove(slot, out var removed)) _hostCommands.Remove(removed.CommandId);
            return;
        }
        var plan = OverlayHotkeyBindingPolicy.Build(null, false, binding, true);
        if (plan.MenuState != OverlayHotkeyBindingState.Ready || plan.MenuHotkey is not { } chord)
            throw new ArgumentException("Invalid Host hotkey.", nameof(binding));
        var parsed = chord.ToGameCompatibleBinding();
        if (primary.Concat(Menu.Values).Concat(Host.Values.Where(r => r.Slot != slot)
                .Select(r => new GameCompatibleHotkeyRoute(r.CommandId, r.Binding)))
            .Any(r => r.Binding == parsed)) throw new InvalidOperationException("Host hotkey conflict.");
        var route = new HostRoute(slot, AllocateHostCommand(ref _lastHostCommand), parsed, lease);
        if (Host.TryGetValue(slot, out var replaced)) _hostCommands.Remove(replaced.CommandId);
        Host[slot] = route;
        _hostCommands.Add(route.CommandId, route);
    }

    internal GameCompatibleHotkeyRoute[] Build(IEnumerable<GameCompatibleHotkeyRoute> primary)
    {
        var routes = primary.Concat(Menu.Values).ToList();
        foreach (var route in Host.Values)
        {
            if (routes.Any(r => r.Binding == route.Binding))
            {
                Diagnostic("host-hotkey-conflict");
                continue;
            }
            routes.Add(new(route.CommandId, route.Binding));
        }
        return routes.ToArray();
    }

    internal void Trigger(int command, Action<int, long> host, Action<int> menu, Action<Action>? enqueue = null)
    {
        if (_hostCommands.TryGetValue(command, out var route))
        {
            // Capture the route on the control thread, before entering the pool.
            // Replacement/removal must not retag an already queued press.
            var lease = route.Lease;
            void Callback()
            {
                try { host(route.Slot, lease); }
                catch { Diagnostic("host-hotkey-callback-failed"); }
            }
            if (enqueue is null) ThreadPool.QueueUserWorkItem(_ => Callback());
            else enqueue(Callback);
        }
        else if (Menu.ContainsKey(command)) menu(command);
        else if (command >= 1000)
            Diagnostic($"host-hotkey-stale-command command={command}");
    }
}

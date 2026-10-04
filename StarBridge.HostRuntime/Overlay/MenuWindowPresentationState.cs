namespace StarBridge.HostRuntime.Overlay;

// Presentation observation only, not permission to send messages or play audio.
// Each authenticated primary lease owns a separate instance.
internal sealed class MenuWindowPresentationState
{
    private readonly object _gate = new();
    private long _request;
    private int _phase;
    internal bool Visible { get { lock (_gate) return _phase == 2; } }

    internal void Observe(long request, string phase, long window)
    {
        var next = phase switch { "opening" => 1, "visible" when window > 0 => 2, "closed" => 3, _ => 0 };
        if (request <= 0 || next == 0) return;
        lock (_gate)
        {
            if (request < _request || (request == _request && next <= _phase)) return;
            _request = request;
            _phase = next;
        }
    }
}

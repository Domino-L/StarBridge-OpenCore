namespace StarBridge.Core.Tools;

/// <summary>SCM's public calibration, not an observation of a player's hangar.</summary>
public sealed record ExecHangarConfig(string Version, string LastModified, string? SourceUrl,
    DateTimeOffset InitialOpenTime, int CycleDriftMs, int DesignOnlineMin,
    int DesignOfflineMin, int CycleNumberOffset, bool Stale = false)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(Version) || Version.Length > 80 || LastModified is null || LastModified.Length > 120 ||
            InitialOpenTime.Year is < 2020 or > 2100 || DesignOnlineMin is < 1 or > 1440 ||
            DesignOfflineMin is < 1 or > 1440 || Math.Abs((long)CycleDriftMs) > 60000 ||
            Math.Abs((long)CycleNumberOffset) > 1000000 ||
            SourceUrl is not null && (SourceUrl.Length > 2048 || !Uri.TryCreate(SourceUrl, UriKind.Absolute, out var uri) ||
                uri.Scheme != "https" || uri.UserInfo.Length != 0)) throw new ArgumentException("Invalid hangar calibration.");
    }
}

public sealed record ExecHangarReminders(bool Enabled = false, bool OnOpen = true,
    bool BeforeOpen = true, int BeforeOpenMinutes = 5, bool BeforeChange = true, int BeforeChangeMinutes = 5,
    bool? BeforeClose = null, int? BeforeCloseMinutes = null, bool OnClose = false, bool LeaveWarning = false,
    bool AutoDuringGame = false)
{
    public bool CloseEnabled => BeforeClose ?? BeforeChange;
    public int CloseMinutes => BeforeCloseMinutes ?? BeforeChangeMinutes;
    public void Validate()
    {
        if (BeforeOpenMinutes is < 1 or > 120 || BeforeChangeMinutes is < 1 or > 120 || CloseMinutes is < 1 or > 120)
            throw new ArgumentException("Reminder lead time must be between 1 and 120 minutes.");
    }
    public bool HasRules => OnOpen || BeforeOpen || BeforeChange || OnClose || CloseEnabled || LeaveWarning;
}
public sealed record ExecHangarPhase(DateTimeOffset Start, DateTimeOffset End, bool Open,
    int GreenLights, int RedLights, long Cycle);
public sealed record ExecHangarWindow(DateTimeOffset Open, DateTimeOffset Close, long Cycle);
public sealed record ExecHangarNotice(DateTimeOffset Due, DateTimeOffset Boundary, string Kind, bool Opening)
{
    public string Key => $"{Boundary.ToUnixTimeMilliseconds()}:{Kind}";
}

/// <summary>One authoritative calculator. Mirrors SCM's millisecond rounding and normalized modulo.</summary>
public sealed class ExecHangarSchedule
{
    private readonly ExecHangarConfig _config;
    public long CycleMs { get; }
    public long OpenMs { get; }
    public ExecHangarSchedule(ExecHangarConfig config)
    {
        config.Validate(); _config = config;
        var design = (config.DesignOnlineMin + config.DesignOfflineMin) * 60000L;
        CycleMs = design + config.CycleDriftMs;
        OpenMs = (long)Math.Floor(CycleMs * (config.DesignOnlineMin * 60000d / design) + .5);
        if (OpenMs <= 0 || CycleMs <= OpenMs) throw new ArgumentException("Invalid hangar cycle.");
    }
    private long Index(DateTimeOffset now) => (long)Math.Floor((now.ToUnixTimeMilliseconds() -
        _config.InitialOpenTime.ToUnixTimeMilliseconds()) / (double)CycleMs);
    private DateTimeOffset Start(long index) => _config.InitialOpenTime.AddMilliseconds(checked(index * CycleMs));
    public IReadOnlyList<ExecHangarWindow> Windows(DateTimeOffset now, int count = 6) =>
        Enumerable.Range(0, count).Select(i => {
            var index = Index(now) + i; var start = Start(index);
            return new ExecHangarWindow(start, start.AddMilliseconds(OpenMs), index + _config.CycleNumberOffset);
        }).ToArray();
    public IReadOnlyList<ExecHangarPhase> Phases(DateTimeOffset now)
    {
        var result = new List<ExecHangarPhase>();
        for (var i = Index(now); i <= Index(now) + 1; i++) {
            var start = Start(i); var cycle = i + _config.CycleNumberOffset;
            double[] fractions = [0, 12d / 65, 24d / 65, 36d / 65, 48d / 65, 60d / 65, 1];
            for (var stage = 0; stage < 6; stage++) result.Add(new(
                start.AddMilliseconds(Math.Ceiling(OpenMs * fractions[stage])),
                start.AddMilliseconds(Math.Ceiling(OpenMs * fractions[stage + 1])), true, 5 - stage, 0, cycle));
            var close = start.AddMilliseconds(OpenMs); var closed = CycleMs - OpenMs;
            for (var stage = 0; stage < 5; stage++) result.Add(new(
                close.AddMilliseconds(Math.Ceiling(closed * stage / 5d)),
                close.AddMilliseconds(Math.Ceiling(closed * (stage + 1) / 5d)), false, stage, 5 - stage, cycle));
        }
        return result;
    }
    public IReadOnlyList<ExecHangarNotice> Due(DateTimeOffset after, DateTimeOffset now, ExecHangarReminders settings)
    {
        settings.Validate();
        // A resumed/suspended or clock-adjusted process never replays a backlog.
        if (!settings.Enabled || now <= after || now - after > TimeSpan.FromSeconds(90)) return [];
        return Notices(after, now.AddMinutes(120), settings)
            .Where(n => n.Due > after && n.Due <= now).OrderBy(n => n.Due).ToArray();
    }
    public IReadOnlyList<ExecHangarNotice> Notices(DateTimeOffset from, DateTimeOffset through, ExecHangarReminders settings)
    {
        settings.Validate();
        if (through < from || through - from > TimeSpan.FromDays(4)) throw new ArgumentException("Invalid monitoring interval.");
        var result = new List<ExecHangarNotice>();
        void Add(DateTimeOffset boundary, string kind, int lead, bool opening) {
            if (boundary >= from && boundary <= through) result.Add(new(boundary.AddMinutes(-lead), boundary, kind, opening));
        }
        for (var index = Index(from) - 1; index <= Index(through) + 1; index++) {
            var start = Start(index); var close = start.AddMilliseconds(OpenMs);
            if (settings.OnOpen) Add(start, "open", 0, true);
            if (settings.BeforeOpen) Add(start, "beforeOpen", settings.BeforeOpenMinutes, true);
            if (settings.BeforeChange) {
                Add(start, "beforeChange", settings.BeforeChangeMinutes, true);
            }
            if (settings.CloseEnabled) Add(close, settings.BeforeClose is null ? "beforeChange" : "beforeClose", settings.CloseMinutes, false);
            if (settings.OnClose) Add(close, "close", 0, false);
            // The final open phase begins when all five lights go out. Use the
            // same rounded boundary as Phases, rather than a separate five-minute timer.
            if (settings.LeaveWarning && close >= from && close <= through)
                result.Add(new(start.AddMilliseconds(Math.Ceiling(OpenMs * (60d / 65))), close, "leave", false));
        }
        return result.OrderBy(n => n.Due).ToArray();
    }
}

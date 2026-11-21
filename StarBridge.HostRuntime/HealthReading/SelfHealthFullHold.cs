namespace StarBridge.HostRuntime.HealthReading;

// Where the player is, from the local game log (SelfHealthLifeContext). Unknown: no log facts (journal unavailable,
// or nothing since the game or the Host started).
internal enum SelfHealthPresence
{
    Unknown,
    Away,
    InUniverse,
}

// Revision changes with every log event that may mean health is no longer full: a death, downed, revived, joining or
// leaving a server, the game starting or stopping. LifeStart changes when a new life begins (a respawn, or the first
// location after joining a server); NewLifeOpen stays true until one of the Revision events comes. Joins counts the
// "joined a server" lines (the reader starts its tile search afresh for each). Only the order of events is used, never
// their times.
internal sealed record SelfHealthLife(SelfHealthPresence Presence, bool Dead, long Revision, long LifeStart = 0, bool NewLifeOpen = false,
    long Joins = 0)
{
    public static readonly SelfHealthLife Unknown = new(SelfHealthPresence.Unknown, false, 0);
}

// What the visor shows when the health tile is not on screen or not read. At full health the game folds the tile away
// (icon and digits); an injured player always has it shown (user's recording 03-28; user 11-13: "我满血时游戏里也不会显示
// 血量圈").
//
// "full" from the screen (after review rounds 1-13): two new images in a row whose clear digits read 99 or more while the
// shown value is full too. Cleared by any reading below full (clear digits; with only the ring: a shown value below
// full), by any log event that may end full health (a death, downed, revived, server change, game start or stop;
// whenever it arrives), and when the switch goes off or the game closes (Forget). Kept while the tile is folded away; a
// tile on screen that cannot be read hides it (an injured player's tile must not show full).
//
// "New life" from the log (11-17 user, replacing the 11-13 new-life rule: "我们日志检测有进服识别"): the log's first
// location after joining a server, or a respawn, taken in while this hold was watching (not when the switch came on or
// the reader started in the middle of a life), begins a life that is full at once: 100 is shown whether the tile is
// folded away or on screen but not read ("找到但读不出" does not end it). It ends with a reading below full (clear
// digits, a clear low ring, or a shown value below full), any of the log events above, or the switch going off. A
// reading of 99 or more goes on showing 100. Only where this computer has read clear digits before at this capture size
// (readableHere; the reader keeps that record), so a screen the reader cannot read never shows a full it cannot check.
//
// A new life does not begin until the reader has watched RecentBelowFullSeconds without a gap since the last reading
// below full (review R1 P1, R2 P1): a death and a respawn line taken in late together, after the new life was already
// seen hurt, must not show it full; time switched away (no images) does not count, as the facts are only taken in with
// images. A reading of 99 or more in a new life is shown as 100 where the size was read clearly (no 100/99 wobble while
// it lasts). A ring-only reading below 99 ends the new life and the full memory (review R2/R3 P2), without the lock
// (the ring is rough). A reading below full counts also while the log still says away or dead (review R3 P1: a player
// joining hurt is on screen before the spawn line comes); a server join taken in forgets readings from before it (review
// R3 P2: the previous session's injury does not hold back the next one's spawn), except a reading less than
// LateLineSeconds before (review R4 P1: a join and spawn line taken in late together, after the new server was read
// hurt). On a fresh image whose ring alone reads below full the smoothed value is not shown as full (review R4 P1), and a
// value carried from earlier images while the tile is not on screen is shown for CarryWithoutTileSeconds at most (review
// R4 P1: healed to full, the tile folds away, and the smoothing would hold the last lower value for 2 s). Both say
// "drop the kept value" (DropKept) so the reader's 0.6 s short-gap keep does not put the old value back (review R5 P1).
// The new life ends when the game log does not say the player is in a server (logLive false, held for a moment by the
// reader: the log page stopped, the log unreadable, back at the main menu; review R5/R6 P1). A value of full carried
// from earlier images (not read on this one) is never shown on its own: a full ring comes from the full memory or a new
// life only (review R6 P1: the smoothing's last 100 after a ring alone read 95). A lower carried value is shown for
// CarryWithoutTileSeconds at most after the last image that had the tile (review R6 P1: timed from the tile's last
// image, not from the first image without it).
//
// "Injured lock": once a new image reads below full (clear digits, or a ring clearly low), no full value is shown at
// all (the recognizer's smoothed value, a carried value, the memory, a new life) until two new images in a row read full
// from clear digits again (review round 13). A death or other health event lifts it (a new life starts unhurt); a
// respawn alone does not (a respawn line can come late, after the new life was already seen hurt).
// With the tile not on screen (and the image not black, the player not away or dead): full if allowed as above,
// otherwise no ring. Switching away and back with no health event keeps both (11-13 user "甲").
internal sealed class SelfHealthFullHold
{
    public const int FullAt = 99;
    // With only the ring read, a ring estimate below this counts as injured (the ring is rougher than the digits).
    public const double RingInjuredBelow = 90;
    // New images in a row that must read full from clear digits before "full" is set.
    public const int FullReadsNeeded = 2;
    // No new life until this long has been watched without a gap since a reading below full (log lines come 0.5-1.5 s
    // late, at times far later).
    public const double RecentBelowFullSeconds = 10.0;
    // ...and never within this long (reader clock) after one, whatever came between (log lines can come this late).
    public const double LateLineSeconds = 5.0;
    // A value below full carried from earlier images is shown this long at most after the last image that had the tile
    // (with the image spacing, gone well under 1 s after it; review R5/R6 P1).
    public const double CarryWithoutTileSeconds = 0.5;

    bool _full, _injured, _newLife, _synced;
    long _joins;
    // Watched time (seconds, gaps not counted) since the last reading below full; infinite: none seen.
    double _watchedSinceBelowFull = double.PositiveInfinity, _lastStepAt = double.NaN;
    // Reader clock of the last reading below full, and of the last new image that had the tile.
    double _belowFullAt = double.NegativeInfinity, _lastTileAt = double.NegativeInfinity;
    int _fullReads;
    long _revision, _lifeStart;

    internal bool Full => _full;
    internal bool Injured => _injured;
    // A life the log began while watching, with nothing since that ends it (11-17 new-life rule).
    internal bool NewLife => _newLife;
    // The newest log revision taken in; a newer one in the life facts means events not yet taken in.
    internal long Revision => _revision;

    // What this step returned and why (diagnostics).
    internal SelfHealthHoldOutcome Last { get; private set; }
    // This step would have shown the new life's 100 but this capture size has never been read clearly (diagnostics).
    internal bool NewLifeWaitingForSize { get; private set; }
    // This step dropped a value on purpose: the reader's short-gap keep must not show the previous one (review R5 P1).
    internal bool DropKept { get; private set; }

    // The switch went off or the game closed. With the life facts, they are taken as seen: a life that began before
    // now was not watched begin. Without them, the next step takes the facts it gets as seen.
    public void Forget(SelfHealthLife? life = null)
    {
        _full = false; _fullReads = 0; _newLife = false;
        // A server joined meanwhile: the previous server's injury is not carried into it (review R4 P2).
        if (life != null && _synced && life.Joins != _joins) { _injured = false; _watchedSinceBelowFull = double.PositiveInfinity; }
        if (life != null) { _revision = life.Revision; _lifeStart = life.LifeStart; _joins = life.Joins; _synced = true; }
        else _synced = false;
        Last = SelfHealthHoldOutcome.None;
        NewLifeWaitingForSize = false;
    }

    // The game log has not said the player is in a server for a while (review R6 P1): the new life's full ends.
    internal void EndNewLife() => _newLife = false;

    // Tests only: as if new images had just read full.
    internal void RememberFullForTest() { _full = true; _injured = false; }

    // display: the recognizer's value (null: none; its own "folded away after full" 100 is passed as null); evidence:
    // this image itself gave digits or a ring; tileFound: the health tile is in this image, read or not; black: the
    // whole image is black; newFrame: a new image; frameDigits / frameRing: what this image's digits / ring read (null:
    // not read); now: reader clock (seconds); continuous: the reader's previous step read an image too, shortly before
    // (no gap: switched away, switch off, capture failing, no new image, a stall); readableHere: this computer has read
    // clear digits at the current capture size before (the new life's 100 needs it); logLive: the game log is being read
    // (false ends a new life and none begins).
    public int? Next(int? display, bool evidence, bool tileFound, bool black, bool newFrame, int? frameDigits, SelfHealthLife life,
        double now = 0, bool continuous = true, double? frameRing = null, bool readableHere = false, bool logLive = true)
    {
        NewLifeWaitingForSize = false;
        DropKept = false;
        // A fresh hold (the reader just started) takes the facts as seen: a life that began before was not watched.
        if (!_synced) { _revision = life.Revision; _lifeStart = life.LifeStart; _joins = life.Joins; _synced = true; }
        if (!continuous) _fullReads = 0;
        if (continuous && !double.IsNaN(_lastStepAt) && now > _lastStepAt) _watchedSinceBelowFull += now - _lastStepAt;
        _lastStepAt = now;
        if (life.Joins != _joins) { _joins = life.Joins; _watchedSinceBelowFull = double.PositiveInfinity; }
        var fresh = evidence && newFrame;
        // A reading below full holds back a new life whatever the log says now (review R3 P1).
        var ringBelowFull = fresh && frameDigits is null && frameRing is < FullAt;
        if (fresh && !black && (frameDigits is < FullAt || ringBelowFull || display is < FullAt)) { _watchedSinceBelowFull = 0; _belowFullAt = now; }
        if (life.Revision != _revision)
        {
            _revision = life.Revision;
            _full = false; _fullReads = 0; _injured = false; _newLife = false;
        }
        if (life.LifeStart != _lifeStart)
        {
            // Taken after the revision: a death and respawn (or a join and spawn) taken in together still begin a new
            // life; a new life a later event already closed does not.
            _lifeStart = life.LifeStart;
            _newLife = life.NewLifeOpen && _watchedSinceBelowFull >= RecentBelowFullSeconds && !(now - _belowFullAt < LateLineSeconds);
        }
        if (!logLive && _newLife) DropKept = true;
        if (!life.NewLifeOpen || !logLive) _newLife = false;
        if (life.Presence == SelfHealthPresence.Away || life.Dead)
        {
            _full = false; _fullReads = 0; _newLife = false;
            Last = SelfHealthHoldOutcome.Away;
            return null;
        }
        if (black) { _fullReads = 0; Last = SelfHealthHoldOutcome.Black; return null; }
        if (tileFound && newFrame) _lastTileAt = now;
        var carried = display.HasValue && !(evidence && newFrame);
        // A carried full is never shown on its own (review R6 P1): the full memory or a new life decide below.
        if (carried && display >= FullAt) display = null;
        // A lower value carried while the tile is not on screen: at most CarryWithoutTileSeconds after the tile's last
        // image (review R4/R6 P1).
        else if (carried && !tileFound && now - _lastTileAt >= CarryWithoutTileSeconds - 1e-9)
        {
            display = null; DropKept = true;
        }
        // Full readings must come in a row: any image that is not one (no digits, a ring only, unreadable, no tile)
        // starts the count again, as do a black screen and a gap (review round 14).
        var fullReading = fresh && frameDigits is >= FullAt && display is >= FullAt;
        if (!fullReading) _fullReads = 0;
        if (fresh)
        {
            if (frameDigits is { } digits)
            {
                if (digits < FullAt) Hurt();
                else if (fullReading && ++_fullReads >= FullReadsNeeded) { _full = true; _injured = false; }
            }
            else if (frameRing is < RingInjuredBelow) Hurt();
            else if (display is < FullAt) { _full = false; _fullReads = 0; _newLife = false; }
            // A ring-only reading below full ends the new life and the full memory even before the smoothed value
            // follows (review R2 P2, R3 P2).
            if (ringBelowFull) { _full = false; _fullReads = 0; _newLife = false; }
        }
        if (display is { } value)
        {
            if (value >= FullAt && _injured) { Last = SelfHealthHoldOutcome.TileUnread; return null; }
            // the ring alone reads below full: the smoothed full is not shown (review R4 P1)
            if (fresh && ringBelowFull && value >= FullAt) { DropKept = true; Last = SelfHealthHoldOutcome.TileUnread; return null; }
            if (fresh) { Last = SelfHealthHoldOutcome.Reading; return InNewLife(value, readableHere); }
            // Carried over from earlier images (below full only, see above): shown for the short smoothing.
            Last = SelfHealthHoldOutcome.Carried;
            return InNewLife(value, readableHere);
        }
        if (tileFound) return NewLifeOr(SelfHealthHoldOutcome.TileUnread, readableHere);
        if (_full && !_injured) { Last = SelfHealthHoldOutcome.Held; return 100; }
        return NewLifeOr(SelfHealthHoldOutcome.NoTile, readableHere);
    }

    // In a new life a value of 99 or more is shown as 100 (11-17 user: "99 以上继续画 100"), where this size was read
    // clearly (review R2 P2: never a full the size check did not allow).
    int InNewLife(int value, bool readableHere) => _newLife && readableHere && value >= FullAt ? 100 : value;

    // The new life's 100 if it applies here, otherwise nothing with the given outcome.
    int? NewLifeOr(SelfHealthHoldOutcome otherwise, bool readableHere)
    {
        if (_newLife && !_injured)
        {
            if (readableHere) { Last = SelfHealthHoldOutcome.NewLifeFull; return 100; }
            NewLifeWaitingForSize = true;
        }
        Last = otherwise;
        return null;
    }

    void Hurt() { _full = false; _fullReads = 0; _injured = true; _newLife = false; }
}

internal enum SelfHealthHoldOutcome
{
    None,
    Reading,
    Held,
    NewLifeFull,
    NoTile,
    TileUnread,
    Carried,
    Black,
    Away,
}

using System.Reflection;
using System.Text;
using StarBridge.HostRuntime.HealthReading;

// "读取自己的血量": recognizer rules, capture lifecycle, model file and privacy guards.
// No game screenshots or game-derived pixels live in these public tests; the real-model
// check runs only where the private model file is present.
internal static class HudHealthTests
{
    internal static Task Run()
    {
        DisplayFollowsDigitsAndIgnoresGlitches();
        RisesWaitLongerThanDrops();
        RingDisagreementPicksTheCloserReading();
        ColourPlusFindsThePlusAndRejectsFilledCorners();
        AlternateIconNeedsAStrongMatch();
        AlternateIconWithoutAReadingIsRejected();
        AlternateTemplatesAreOptionalButComplete();
        InPlaceReadingOnlyWhileBleedingIsPlausible();
        StaleRingDoesNotHoldDigitsOnBrightBackground();
        BrightBackgroundMarksTheRingEvenWhenItWasNotRead();
        LifecycleCapturesOnlyWhenAllowedAndReleasesEverything();
        MissingModelNeverStartsCapture();
        OnlyNewImagesKeepTheRingAndALostWindowIsReplaced();
        FullHoldFollowsClearDigitsOnly();
        NewLifeFromTheLogIsFull();
        FilterMarksItsFoldedAwayFull();
        CarriedValuesNeverRefreshTheMemory();
        LifeContextFollowsTheGameLog();
        LateEventsOnlyEverClearFull();
        ServiceShowsFullWhenTheTileIsFoldedAndCountsWithoutValues();
        ServiceKeepsTheRingOverAShortGapOnly();
        ServiceNewLifeFromTheLogIsFull();
        ReadableSizesKeepSizesOnly();
        ServiceNewLifeEdges();
        CaptureErrorsReleaseTheSourceAndRetry();
        BlockedCaptureIsReleasedOnlyByTheReader();
        PromptDisposeFreesTheCancellationSource();
        DisposeWaitsForAPublishInFlightAndNothingValidFollows();
        StopResetsTheDigitScale();
        ModelFileRoundTripsAndRejectsDamage();
        ModelWithWrongNetworkShapeIsRejected();
        PanelScalerKeepsLayout();
        HealthNeverReachesSharedOrRelayTypes();
        VisorMappingFollowsTheRingRules();
        PrivateModelMatchesTrainingOutput();
        OffHomeFindsNeedTheRingOrTheConfirmedPlace();
        ANewLifeKeepsTheConfirmedPlace();
        BigDropsWaitLongerAndShortBurstsNeverShow();
        DiagnosticsCountGuardsWithoutValues();
        return Task.CompletedTask;
    }

    // ---- 11-14 user: "突然识别出极低血量 但当前血量正常" -------------------------------------------
    // 98q recording 433 s: the tile was lost for a moment, the colour search over the whole panel took the
    // neighbouring tile (no ring, a percent sign, "1") and the display showed 1 for 13 s while health was about 84.

    static void OffHomeFindsNeedTheRingOrTheConfirmedPlace()
    {
        AssertEqual(false, HudHealthRecognizer.AcceptOffHome(126, false), "far from the confirmed place, no ring: refused");
        AssertEqual(true, HudHealthRecognizer.AcceptOffHome(126, true), "far, with a ring: taken");
        AssertEqual(true, HudHealthRecognizer.AcceptOffHome(3, false), "near the confirmed place (colour vs edge position differ by up to ~3 px), no ring: taken");
        AssertEqual(false, HudHealthRecognizer.AcceptOffHome(14, false), "98q: after a HUD layout change another tile's cross sits ~14 px from the old place: refused");
        AssertEqual(true, HudHealthRecognizer.AcceptOffHome(HudHealthRecognizer.ConfirmedNearPx, false), "at the edge of near: taken");
        AssertEqual(false, HudHealthRecognizer.AcceptOffHome(null, false), "no confirmed place yet, no ring: refused");
        AssertEqual(true, HudHealthRecognizer.AcceptOffHome(null, true), "no confirmed place yet, with a ring: taken");

        // Through the recognizer: the alternate icon (same rule as the colour search) at (300, 250) with a percent sign
        // and a valid reading below it (the synthetic network reads 0), on a dark plain floor (no ring).
        var frame = AltPanel(true);
        var m0 = SyntheticModel(); var pct = m0.Pct[0];
        for (int y = 0; y < pct.H; y++)
            for (int x = 0; x < pct.W; x++)
            {
                int j = ((250 + 36 + 6 + y) * HudPanelFrame.W + 300 - 46 + 50 + x) * 3; byte v = (byte)pct.Data[y * pct.W + x];
                frame.Bgr[j] = v; frame.Bgr[j + 1] = v; frame.Bgr[j + 2] = v;
            }
        const BindingFlags any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        HudHealthSample Run(double? confirmedX)
        {
            var rec = new HudHealthRecognizer(HudHealthModel.Load(new MemoryStream(SyntheticModelBytes(AltBlocks()))));
            if (confirmedX is double cx)
            {
                typeof(HudIconLocator).GetField("confCx", any)!.SetValue(rec.Loc, cx);
                typeof(HudIconLocator).GetField("confCy", any)!.SetValue(rec.Loc, 250.0);
            }
            var r = rec.Process(frame, 0, 8);
            if (r.OffHomeRejected) AssertEqual(-1.0, (double)typeof(HudIconLocator).GetField("homeCx", any)!.GetValue(rec.Loc)!, "a refused find leaves the remembered position as it was");
            return r;
        }
        var none = Run(null);
        AssertEqual(true, none.OffHomeRejected, "no confirmed place, no ring: the find is refused");
        AssertEqual("not_found", none.State, "refused: nothing is read there");
        AssertEqual<int?>(null, none.CnnRaw, "refused: no digits kept");
        var far = Run(426);
        AssertEqual(true, far.OffHomeRejected, "126 px from the confirmed place (the next tile), no ring: refused");
        var moved = Run(314);
        AssertEqual(true, moved.OffHomeRejected, "14 px from the confirmed place (another tile after a layout change), no ring: refused");
        var near = Run(302);
        AssertEqual(false, near.OffHomeRejected, "at the confirmed place: taken as before");
        AssertEqual<int?>(0, near.CnnRaw, "at the confirmed place: the digits are read");
        AssertEqual(true, near.State is "ok" or "no_ring", $"at the confirmed place the tile counts as found ({near.State})");

        // Review P2: a find taken because its ring was read becomes the confirmed place, so the same place is taken later
        // when the ring is empty (low health on a bright floor), even if only the colour or alternate search finds it.
        var ringed = new HudPanelFrame(); Buffer.BlockCopy(frame.Bgr, 0, ringed.Bgr, 0, frame.Bgr.Length);
        for (int a = 0; a < 720; a++)
            for (double rr = 29; rr <= 31; rr += 0.5)
            {
                int x = (int)Math.Round(300 + rr * Math.Sin(a * Math.PI / 360)), y = (int)Math.Round(250 - rr * Math.Cos(a * Math.PI / 360));
                int j = (y * HudPanelFrame.W + x) * 3; ringed.Bgr[j] = 235; ringed.Bgr[j + 1] = 235; ringed.Bgr[j + 2] = 235;
            }
        var rec2 = new HudHealthRecognizer(HudHealthModel.Load(new MemoryStream(SyntheticModelBytes(AltBlocks()))));
        var first = rec2.Process(ringed, 0, 8);
        AssertEqual(false, first.OffHomeRejected, $"no confirmed place, but a ring is read: taken (arc {first.ArcDeg})");
        if (rec2.Loc.Confirmed is not { } cf || Math.Abs(cf.cx - 300) > 3 || Math.Abs(cf.cy - 250) > 3)
            throw new InvalidOperationException($"a ring-backed find becomes the confirmed place: {rec2.Loc.Confirmed}");
        var later = rec2.Process(frame, 0.125, 8);
        AssertEqual(false, later.OffHomeRejected, "the same place later without a ring: taken");
        AssertEqual<int?>(0, later.CnnRaw, "and read");
        Console.WriteLine("PASS own health a find away from the confirmed tile needs a ring (another tile's percent is not read)");
    }

    // A new life only restarts the estimate; stopping capture forgets the confirmed place (window or HUD scale may change).
    static void ANewLifeKeepsTheConfirmedPlace()
    {
        var rec = new HudHealthRecognizer(SyntheticModel());
        const BindingFlags any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        typeof(HudIconLocator).GetField("confCx", any)!.SetValue(rec.Loc, 339.0);
        typeof(HudIconLocator).GetField("confCy", any)!.SetValue(rec.Loc, 250.0);
        typeof(HudIconLocator).GetField("homeCx", any)!.SetValue(rec.Loc, 339.0);
        typeof(HudIconLocator).GetField("homeCy", any)!.SetValue(rec.Loc, 250.0);
        double t = 0;
        for (int i = 0; i < 24; i++, t += 0.125) rec.Filter.Step(Sample(t, 70), 8);
        rec.ResetEstimate();
        AssertEqual<int?>(null, rec.Filter.Shown, "a new life restarts the estimate");
        AssertEqual(true, rec.Loc.Confirmed is { cx: 339.0 }, "a new life keeps the confirmed place");
        AssertEqual(339.0, rec.Loc.Home.cx, "a new life keeps the remembered position");
        rec.Reset();
        AssertEqual(true, rec.Loc.Confirmed is null, "stopping capture forgets the confirmed place");

        // Through the reader: a health event (revision change) keeps it; the switch going off clears it.
        bool enabled = true;
        var life = Life(1);
        var service = new SelfHealthReadingService(() => enabled, () => true, () => true, SyntheticModel, new GrayFactory(), _ => { }) { Life = () => life };
        service.Step(0.125);
        var loc = service.Recognizer?.Loc ?? throw new InvalidOperationException("recognizer created while capturing");
        typeof(HudIconLocator).GetField("confCx", any)!.SetValue(loc, 339.0);
        typeof(HudIconLocator).GetField("confCy", any)!.SetValue(loc, 250.0);
        life = Life(2);
        service.Step(0.25);
        AssertEqual(true, loc.Confirmed is { cx: 339.0 }, "a death or respawn keeps the confirmed place");
        // 11-17 user: a server join starts the tile search afresh, and the first spawn after it again (loading screens
        // in between); a respawn after that keeps it.
        void Confirm() { typeof(HudIconLocator).GetField("confCx", any)!.SetValue(loc, 339.0); typeof(HudIconLocator).GetField("confCy", any)!.SetValue(loc, 250.0); }
        life = Life(3, SelfHealthPresence.Away, joins: 1);
        service.Step(0.26);
        AssertEqual(true, loc.Confirmed is null, "a server join forgets the confirmed place");
        Confirm();
        service.Step(0.27);
        AssertEqual(true, loc.Confirmed is { cx: 339.0 }, "loading, no new facts: kept");
        life = Life(3, lifeStart: 1, newLife: true, joins: 1);
        service.Step(0.28);
        AssertEqual(true, loc.Confirmed is null, "the first spawn after the join forgets it again");
        Confirm();
        life = Life(4, dead: true, lifeStart: 1, joins: 1);
        service.Step(0.29);
        life = Life(4, lifeStart: 2, newLife: true, joins: 1);
        service.Step(0.30);
        AssertEqual(true, loc.Confirmed is { cx: 339.0 }, "a respawn keeps it (11-14: no misreading a neighbouring tile after a death)");
        enabled = false;
        service.Step(0.375);
        AssertEqual(true, loc.Confirmed is null, "the switch going off (capture stops) forgets it");
        service.Dispose();
        Console.WriteLine("PASS own health a new life keeps the confirmed tile place; stopping capture forgets it");
    }

    static void BigDropsWaitLongerAndShortBurstsNeverShow()
    {
        const double hz = 8;
        // A drop of 20: shown, but not before SettleBigDown after the estimate moved (at least 3 frames), and only once.
        var f = new SelfHealthFilter(); double t = 0;
        FramesUntil(f, ref t, hz, 80, -99, max: 40);
        int to60 = -1, shownCount = 0;
        for (int i = 0; i < 16; i++, t += 1 / hz)
        {
            var s = Sample(t, 60); f.Step(s, hz);
            if (s.BigDropShown) shownCount++;
            if (to60 < 0 && s.Display == 60) to60 = i;
        }
        if (to60 < 3 || to60 > 8) throw new InvalidOperationException($"a drop of 20 is shown after {to60} frames (expected 3..8)");
        AssertEqual(1, shownCount, "one big drop shown once");

        // A short burst of a wrong tile's "1" on a bright floor (no ring to compare): the old 1-frame wait shows it,
        // the new wait never does; the started confirmation is dropped.
        (bool everShown, int started, int shown, int dropped) Burst(SelfHealthFilter g, int frames)
        {
            double tb = 0; bool seen = false; int st = 0, sh = 0, dr = 0;
            FramesUntil(g, ref tb, hz, 84, -99, max: 40);
            void Count(HudHealthSample s) { if (s.BigDropStarted) st++; if (s.BigDropShown) sh++; if (s.BigDropAbandoned) dr++; if (s.Display is < 50) seen = true; }
            for (int i = 0; i < frames; i++, tb += 1 / hz)
            {
                var s = Sample(tb, 1); s.RingEst = null; s.ArcDeg = -1; s.RingUnreliable = true; g.Step(s, hz); Count(s);
            }
            for (int i = 0; i < 16; i++, tb += 1 / hz) { var s = Sample(tb, 84); g.Step(s, hz); Count(s); }
            return (seen, st, sh, dr);
        }
        var oldWait = Burst(new SelfHealthFilter { SettleBigDown = 0, SettleDeepDown = 0 }, 8);
        AssertEqual(true, oldWait.everShown, "control: with the old 1-frame wait an 8-frame burst of 1 is shown");
        var burst = Burst(new SelfHealthFilter(), 8);
        AssertEqual(false, burst.everShown, "an 8-frame burst of 1 (one second) is never shown");
        AssertEqual(0, burst.shown, "no big drop shown");
        if (burst.started < 1 || burst.started != burst.dropped) throw new InvalidOperationException($"started {burst.started}, dropped {burst.dropped}");

        // A deep drop that lasts: about a second without a ring to agree; faster when the ring reads the same.
        int DeepFrames(bool ring)
        {
            var g = new SelfHealthFilter(); double tg = 0;
            FramesUntil(g, ref tg, hz, 84, -99, max: 40);
            for (int i = 0; i < 32; i++, tg += 1 / hz)
            {
                var s = Sample(tg, 5);
                if (!ring) { s.RingEst = null; s.ArcDeg = -1; s.RingUnreliable = true; }
                g.Step(s, hz);
                if (s.Display == 5) return i;
            }
            return -1;
        }
        int deepNoRing = DeepFrames(false), deepRing = DeepFrames(true);
        if (deepNoRing < 8 || deepNoRing > 14) throw new InvalidOperationException($"a deep drop without a ring is shown after {deepNoRing} frames (expected 8..14)");
        if (deepRing < 3 || deepRing >= deepNoRing) throw new InvalidOperationException($"a deep drop the ring agrees with is shown after {deepRing} frames (no ring {deepNoRing})");

        // A real drop whose readings wobble between neighbours is not held up by the wobble.
        var w = new SelfHealthFilter(); double tw = 0;
        FramesUntil(w, ref tw, hz, 80, -99, max: 40);
        int wob = -1;
        int[] seq = { 60, 61, 60, 59 };
        for (int i = 0; i < 24 && wob < 0; i++, tw += 1 / hz)
        {
            var s = Sample(tw, seq[i % seq.Length], ring: 60); w.Step(s, hz);
            if (s.Display is >= 58 and <= 62) wob = i;
        }
        if (wob < 0 || wob > 8) throw new InvalidOperationException($"a wobbling drop is shown after {wob} frames (expected at most 8)");

        // Review P2: readings wobbling across the Big boundary (80 shown, 65 and 66 in turn) do not keep restarting the wait.
        var edge = new SelfHealthFilter(); double te = 0;
        FramesUntil(edge, ref te, hz, 80, -99, max: 40);
        int edgeAt = -1;
        for (int i = 0; i < 24 && edgeAt < 0; i++, te += 1 / hz)
        {
            int v = i % 2 == 0 ? 65 : 66;
            var s = Sample(te, v, ring: v); edge.Step(s, hz);
            if (s.Display is 65 or 66) edgeAt = i;
        }
        if (edgeAt < 0 || edgeAt > 8) throw new InvalidOperationException($"a drop wobbling across the boundary is shown after {edgeAt} frames (expected at most 8)");

        // Review P2: right after a rise, a misread far below is still held; going back to where it was before the rise is quick.
        var rise = new SelfHealthFilter(); double tr = 0;
        FramesUntil(rise, ref tr, hz, 80, -99, max: 40);
        FramesUntil(rise, ref tr, hz, 83, 83, max: 24);
        var afterRise = (everShown: false, shown: 0);
        for (int i = 0; i < 8; i++, tr += 1 / hz)
        {
            var s = Sample(tr, 1); s.RingEst = null; s.ArcDeg = -1; s.RingUnreliable = true; rise.Step(s, hz);
            if (s.Display is < 50) afterRise.everShown = true;
            if (s.BigDropShown) afterRise.shown++;
        }
        AssertEqual(false, afterRise.everShown, "a burst of 1 right after a rise is not shown");
        var back = new SelfHealthFilter(); double tk = 0;
        FramesUntil(back, ref tk, hz, 60, -99, max: 40);
        FramesUntil(back, ref tk, hz, 84, 84, max: 24);
        int backDown = FramesUntil(back, ref tk, hz, 60, 60, max: 24);
        if (backDown < 0 || backDown >= to60) throw new InvalidOperationException($"going back down to the value before a rise is slow: {backDown} frames (a fresh drop of 20: {to60})");

        // 98q 1165 s: three black frames in the middle of a real drop do not restart the wait.
        var bk = new SelfHealthFilter(); double tbk = 0;
        FramesUntil(bk, ref tbk, hz, 80, -99, max: 40);
        bool earlyShown = false;
        for (int i = 0; i < 3; i++, tbk += 1 / hz) { var s = Sample(tbk, 55); bk.Step(s, hz); if (s.Display == 55) earlyShown = true; }
        AssertEqual(false, earlyShown, "control: three frames are not enough before the black");
        for (int i = 0; i < 3; i++, tbk += 1 / hz) bk.Step(new HudHealthSample { T = tbk, State = "black" }, hz);
        int afterBlack = -1;
        for (int i = 0; i < 8 && afterBlack < 0; i++, tbk += 1 / hz) { var s = Sample(tbk, 55); bk.Step(s, hz); if (s.Display == 55) afterBlack = i; }
        // Without the black the drop is shown on frame to60 of 55; three frames of 55 came before the black, so the rest
        // should take no more than to60 - 3 frames (restarting the wait would take 3 or more after the black).
        if (afterBlack < 0 || afterBlack > to60 - 3) throw new InvalidOperationException($"a drop interrupted by a short black is shown {afterBlack} frames after it (expected at most {to60 - 3})");

        // Review P1: the black only pauses the wait. One frame of 55, three black frames, then 55 again: the black time does
        // not count, so it still takes two more frames (counting it would show 55 on the first frame after the black).
        var pause = new SelfHealthFilter(); double tp = 0;
        FramesUntil(pause, ref tp, hz, 80, -99, max: 40);
        bool started = false;
        for (int i = 0; i < 4 && !started; i++, tp += 1 / hz) { var s = Sample(tp, 55); pause.Step(s, hz); started = s.BigDropStarted; AssertEqual(false, s.Display == 55, "control: not shown before the black"); }
        AssertEqual(true, started, "control: the wait starts (stop feeding 55 on the frame it starts)");
        for (int i = 0; i < 3; i++, tp += 1 / hz) { var s = new HudHealthSample { T = tp, State = "black" }; pause.Step(s, hz); AssertEqual(false, s.Display == 55, "nothing changes during the black"); }
        int afterPause = -1;
        for (int i = 0; i < 8 && afterPause < 0; i++, tp += 1 / hz) { var s = Sample(tp, 55); pause.Step(s, hz); if (s.Display == 55) afterPause = i; }
        if (afterPause < 2 || afterPause > 3) throw new InvalidOperationException($"black time counted: shown {afterPause} frames after the black (expected 2..3)");

        // Review REVIEW3: the wait started, then no new image for a second, then one black frame, then 55 again:
        // the gap ends the wait before the black can keep it, so it starts over (3 or more frames).
        var gap = new SelfHealthFilter(); double tg2 = 0;
        FramesUntil(gap, ref tg2, hz, 80, -99, max: 40);
        bool gapStarted = false;
        for (int i = 0; i < 4 && !gapStarted; i++, tg2 += 1 / hz) { var s = Sample(tg2, 55); gap.Step(s, hz); gapStarted = s.BigDropStarted; }
        AssertEqual(true, gapStarted, "control: the wait starts before the gap");
        tg2 += 1.0;
        gap.Step(new HudHealthSample { T = tg2, State = "black" }, hz); tg2 += 1 / hz;
        int afterGap = -1;
        for (int i = 0; i < 8 && afterGap < 0; i++, tg2 += 1 / hz) { var s = Sample(tg2, 55); gap.Step(s, hz); if (s.Display == 55) afterGap = i; }
        if (afterGap < 3) throw new InvalidOperationException($"a sampling gap followed by a black kept the wait: shown {afterGap} frames after (expected 3 or more)");

        // Review P1: different readings before and after the black (55, then 30) do not join into one wait.
        var join = new SelfHealthFilter(); double tj = 0;
        FramesUntil(join, ref tj, hz, 80, -99, max: 40);
        for (int i = 0; i < 3; i++, tj += 1 / hz) join.Step(Sample(tj, 55), hz);
        for (int i = 0; i < 3; i++, tj += 1 / hz) join.Step(new HudHealthSample { T = tj, State = "black" }, hz);
        int afterJoin = -1; bool restarted = false;
        for (int i = 0; i < 8 && afterJoin < 0; i++, tj += 1 / hz)
        {
            var s = Sample(tj, 30); join.Step(s, hz);
            if (s.BigDropAbandoned) restarted = true;
            if (s.Display is int dj && dj <= 35) afterJoin = i;
        }
        AssertEqual(true, restarted, "a different reading after the black restarts the wait");
        if (afterJoin < 3) throw new InvalidOperationException($"readings across a black joined: 30 shown {afterJoin} frames after the black (expected 3 or more)");
        // A long black (0.45 s or more) still clears the display, as before.
        var longBlack = new SelfHealthFilter(); double tl = 0;
        FramesUntil(longBlack, ref tl, hz, 80, -99, max: 40);
        longBlack.Step(Sample(tl, 55), hz); tl += 1 / hz;
        HudHealthSample lb = null!;
        for (int i = 0; i < 5; i++, tl += 1 / hz) { lb = new HudHealthSample { T = tl, State = "black" }; longBlack.Step(lb, hz); }
        AssertEqual<int?>(null, lb.Display, "a long black clears the display");
        Console.WriteLine($"PASS own health big drops wait longer, short bursts never show (drop 20 after {to60}, deep {deepNoRing}/{deepRing} frames, wobble {wob}, after black {afterBlack}, paused {afterPause}, different readings {afterJoin})");
    }

    static void DiagnosticsCountGuardsWithoutValues()
    {
        var lines = new List<string>();
        var d = new SelfHealthDiagnostics(lines.Add);
        d.CaptureStarted(0);
        for (int i = 0; i < 5; i++)
        {
            d.Read(0.1 * i, true, "not_found", false, SelfHealthHoldOutcome.NoTile, 3);
            d.Guards(offHomeRejected: i < 2, bigDropStarted: i == 2, bigDropShown: false, bigDropAbandoned: i == 4);
        }
        d.Guards(false, true, true, false);
        for (int i = 0; i < 3; i++) { d.RingChange(true, true); d.RingChange(false, true); }   // 11-15: a 100/99 wobble
        d.RingChange(true, false);                       // a drop lower down
        d.Read(0.6, true, "not_found", false, SelfHealthHoldOutcome.NoTile, 3, newLifeWaitingForSize: true);
        d.TileSearchRestarted(); d.TileSearchRestarted();
        d.Tick(61);
        var summary = lines.SingleOrDefault(line => line.StartsWith("summary ", StringComparison.Ordinal))
            ?? throw new InvalidOperationException("one summary line after a minute");
        foreach (var part in new[] { "offHomeRejected=2", "bigDropHeld=2", "bigDropShown=1", "bigDropDropped=1" })
            AssertEqual(true, summary.Contains(part, StringComparison.Ordinal), $"summary has {part}: {summary}");
        AssertEqual("4", SummaryFields(summary).GetValueOrDefault("ringDrops"), $"ring drops: {summary}");
        AssertEqual("6", SummaryFields(summary).GetValueOrDefault("nearFullChanges"), $"near-full changes: {summary}");
        AssertEqual("1", SummaryFields(summary).GetValueOrDefault("newLifeWaitingForSize"), $"new life waiting for the size: {summary}");
        AssertEqual("2", SummaryFields(summary).GetValueOrDefault("tileSearchRestarts"), $"tile search restarts: {summary}");
        lines.Clear();
        d.Read(62, true, "not_found", false, SelfHealthHoldOutcome.NoTile, 3);
        d.Tick(123);
        var next = lines.Single(line => line.StartsWith("summary ", StringComparison.Ordinal));
        AssertEqual(true, next.Contains("offHomeRejected=0 bigDropHeld=0 bigDropShown=0 bigDropDropped=0", StringComparison.Ordinal), $"counts start again each minute: {next}");
        AssertEqual(true, next.Contains("ringDrops=0 nearFullChanges=0", StringComparison.Ordinal), $"ring changes start again each minute: {next}");
        AssertEqual("0", SummaryFields(next).GetValueOrDefault("newLifeWaitingForSize"), $"new-life counts start again each minute: {next}");
        AssertEqual("0", SummaryFields(next).GetValueOrDefault("tileSearchRestarts"), $"restart counts start again each minute: {next}");

        // Review P3: a big drop still being confirmed when a new life starts, or when capture stops, counts as dropped.
        var lines2 = new List<string>();
        bool enabled = true;
        var life = Life(1);
        var service = new SelfHealthReadingService(() => enabled, () => true, () => true, SyntheticModel, new GrayFactory(), _ => { })
            { Life = () => life, Diagnostics = new SelfHealthDiagnostics(lines2.Add) };
        const BindingFlags any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        service.Step(0.125);
        var filter = service.Recognizer?.Filter ?? throw new InvalidOperationException("recognizer created while capturing");
        typeof(SelfHealthFilter).GetField("downSince", any)!.SetValue(filter, 0.1);
        life = Life(2);
        service.Step(0.25);
        AssertEqual(false, filter.BigDropPending, "a new life clears the pending big drop");
        typeof(SelfHealthFilter).GetField("downSince", any)!.SetValue(filter, 0.3);
        enabled = false;
        service.Step(0.375);
        enabled = true;
        service.Step(61.5);
        service.Dispose();
        var s2 = lines2.First(line => line.StartsWith("summary ", StringComparison.Ordinal));
        AssertEqual(true, s2.Contains("bigDropDropped=2", StringComparison.Ordinal), $"a new life and a stop each count one dropped: {s2}");
        Console.WriteLine("PASS own health diagnostics count refused finds and held big drops (counts only)");
    }

    // ---- display rules -------------------------------------------------------------------

    static HudHealthSample Sample(double t, int value, double? ring = null, string state = "ok")
    {
        var s = new HudHealthSample { T = t, State = state, Score = 0.8f, Cx = 557, Cy = 287, PctScore = 0.9f, RingEst = ring ?? value, CnnRaw = value };
        var text = value.ToString(System.Globalization.CultureInfo.InvariantCulture);
        for (int k = 0; k < 3; k++)
        {
            var p = Enumerable.Repeat(0.005f, 11).ToArray();
            int c = k < text.Length ? text[text.Length - 1 - k] - '0' : 10;
            p[c] = 0.95f;
            s.Probs[k] = p;
        }
        return s;
    }

    // 11-11 user live test: the HUD showed 71, the ring read ~68, the digit model kept reading 77
    // (ones digit 1 taken for 7, 1 as the runner-up). The display must not sit on 77.
    static void RingDisagreementPicksTheCloserReading()
    {
        static float[] P(params (int c, float p)[] xs)
        {
            var a = new float[11]; float rest = 1 - xs.Sum(x => x.p);
            for (int i = 0; i < 11; i++) a[i] = rest / (11 - xs.Length);
            foreach (var (c, p) in xs) a[c] = p;
            return a;
        }
        foreach (var (hz, ones, allowed, label) in new[]
        {
            (2.0, P((7, 0.90f), (1, 0.08f)), new[] { 71 }, "runner-up 1 at 2 reads per second"),
            (8.0, P((7, 0.90f), (1, 0.08f)), new[] { 71 }, "runner-up 1 at 8 reads per second"),
            (2.0, P((7, 0.99f)), new[] { 66, 67, 68, 69, 70, 71, 72, 73 }, "no runner-up falls back near the ring"),
        })
        {
            var f = new SelfHealthFilter(); int? shown = null;
            for (int i = 0; i < (int)(20 * hz); i++)
            {
                var s = new HudHealthSample { T = i / hz, State = "ok", Score = 0.85f, Cx = 226, Cy = 311, PctScore = 0.91f, RingEst = 68 + (i % 3 - 1) };
                s.Probs[0] = ones; s.Probs[1] = P((7, 0.99f)); s.Probs[2] = P((10, 0.99f));
                f.Step(s, hz); shown = s.Display;
            }
            if (shown is not { } v || !allowed.Contains(v)) throw new InvalidOperationException($"{label}: shown {shown?.ToString() ?? "none"}");
        }
        // Digits and ring a few points apart (normal ring bias): the digits still win.
        var g = new SelfHealthFilter(); int? last = null;
        for (int i = 0; i < 40; i++)
        {
            var s = Sample(i / 8.0, 78, ring: 75 + (i % 3 - 1));
            g.Step(s, 8); last = s.Display;
        }
        AssertEqual(78, last, "digits 78 with ring 75 keep showing 78");
        Console.WriteLine("PASS own health picks the reading closer to the ring when digits and ring disagree");
    }

    // 11-11 live test: on a bright textured floor at low health the edge search lost the icon. The colour
    // search finds a blue-white plus on grey texture, and refuses shapes whose corners are filled
    // (pills, a plus with arrow heads). Synthetic pixels only.
    static void ColourPlusFindsThePlusAndRejectsFilledCorners()
    {
        HudPanelFrame Panel(bool fillCorners)
        {
            var f = new HudPanelFrame(); var rng = new Random(7);
            for (int i = 0; i < f.Bgr.Length; i += 3) { byte g = (byte)(150 + rng.Next(60)); f.Bgr[i] = g; f.Bgr[i + 1] = g; f.Bgr[i + 2] = (byte)Math.Min(255, g + 6); }
            void Px(int x, int y) { int i = (y * HudPanelFrame.W + x) * 3; f.Bgr[i] = 255; f.Bgr[i + 1] = 235; f.Bgr[i + 2] = 150; }
            int cx = 300, cy = 250;
            for (int y = cy - 11; y <= cy + 11; y++) for (int x = cx - 3; x < cx + 3; x++) Px(x, y);
            for (int y = cy - 3; y < cy + 3; y++) for (int x = cx - 11; x <= cx + 11; x++) Px(x, y);
            if (fillCorners)
                foreach (var (dx, dy) in new[] { (-7, -7), (7, -7), (-7, 7), (7, 7) })
                    for (int y = cy + dy - 3; y <= cy + dy + 3; y++) for (int x = cx + dx - 3; x <= cx + dx + 3; x++) Px(x, y);
            return f;
        }
        var cp = new HudColourPlus();
        var hit = cp.Find(HudColourPlus.Map(Panel(false)), 0, 0, HudPanelFrame.W, HudPanelFrame.H, coarse: true);
        if (hit is not { } h || Math.Abs(h.Cx - 300) > 4 || Math.Abs(h.Cy - 250) > 4) throw new InvalidOperationException($"plus not found: {hit}");
        var miss = cp.Find(HudColourPlus.Map(Panel(true)), 0, 0, HudPanelFrame.W, HudPanelFrame.H, coarse: true);
        AssertEqual(null, miss, "a plus with filled corners is not taken for the health icon");
        Console.WriteLine("PASS own health colour search finds the plus on a textured floor and rejects filled corners");
    }

    // User 11-12 ("加进 r6"): damage can take a lot at once, healing climbs slowly. A rise of more than 2 is shown
    // only after the readings have stayed above the display for SettleUp; a drop does not wait; going back up to
    // where it was just before a drop (the drop was probably a misread) is quick again.
    static int FramesUntil(SelfHealthFilter f, ref double t, double hz, int value, int target, double? ring = null, int max = 24)
    {
        for (int i = 0; i < max; i++, t += 1 / hz)
        {
            var s = Sample(t, value, ring); f.Step(s, hz);
            if (s.Display == target) { t += 1 / hz; return i; }
        }
        return -1;
    }

    static void RisesWaitLongerThanDrops()
    {
        const double hz = 8;
        var f = new SelfHealthFilter(); double t = 0;
        // Changes of 10 stay under the "big change needs the ring" rule, so only the waiting differs.
        FramesUntil(f, ref t, hz, 70, -99, max: 40);              // settle on 70 for 5 s
        int drop = FramesUntil(f, ref t, hz, 60, 60);
        FramesUntil(f, ref t, hz, 60, -99, max: 40);              // 5 s at 60, past the reversal window
        int rise = FramesUntil(f, ref t, hz, 70, 70);
        if (drop < 0 || rise < 0) throw new InvalidOperationException($"changes not shown: drop {drop}, rise {rise}");
        if (rise - drop < 1) throw new InvalidOperationException($"a rise is not held longer than a drop: drop {drop}, rise {rise}");
        FramesUntil(f, ref t, hz, 70, -99, max: 40);
        // A short upward misread (two frames of 78 while the ring stays at 70) does not change the display.
        for (int i = 0; i < 2; i++, t += 1 / hz) { var g = Sample(t, 78, ring: 70); f.Step(g, hz); AssertEqual(70, g.Display, "a two-frame upward misread is not shown"); }
        FramesUntil(f, ref t, hz, 70, -99, max: 40);
        // A drop that is undone right away comes back faster than it went (no rise wait).
        int down = FramesUntil(f, ref t, hz, 60, 60);
        int back = FramesUntil(f, ref t, hz, 70, 70);
        if (down < 0 || back < 0 || back >= down) throw new InvalidOperationException($"going back up after a drop is slow: down {down}, back {back}");
        // Review R8: the rise must be seen without a break. Readings above the display, then more than UpGap
        // (0.3 s) with no usable reading, then the rise again: the wait starts over. One lost frame is not a break.
        var plain = new SelfHealthFilter(); double tp = 0;
        FramesUntil(plain, ref tp, hz, 60, -99, max: 40);
        int straight = FramesUntil(plain, ref tp, hz, 70, 70);
        var cut = new SelfHealthFilter(); double tc = 0;
        FramesUntil(cut, ref tc, hz, 60, -99, max: 40);
        for (int i = 0; i < straight; i++, tc += 1 / hz) { var s = Sample(tc, 70); cut.Step(s, hz); AssertEqual(60, s.Display, "not shown before the full wait"); }
        for (int i = 0; i < 3; i++, tc += 1 / hz) { var s = Sample(tc, 70, state: "not_found"); cut.Step(s, hz); }
        int resumed = FramesUntil(cut, ref tc, hz, 70, 70);
        if (resumed < 2) throw new InvalidOperationException($"a rise interrupted by lost frames is shown without a new wait: {resumed} frames (straight {straight})");
        var blip = new SelfHealthFilter(); double tb = 0;
        FramesUntil(blip, ref tb, hz, 60, -99, max: 40);
        for (int i = 0; i < straight - 1; i++, tb += 1 / hz) blip.Step(Sample(tb, 70), hz);
        { var s = Sample(tb, 70, state: "not_found"); blip.Step(s, hz); tb += 1 / hz; }
        int afterBlip = FramesUntil(blip, ref tb, hz, 70, 70);
        if (afterBlip < 0 || afterBlip >= resumed) throw new InvalidOperationException($"one lost frame restarted the wait: {afterBlip} frames (after a long break {resumed})");
        // Review R9: at a low rate (2 a second) frames are 0.5 s apart; that is not a break, the rise is shown.
        var slow = new SelfHealthFilter(); double ts = 0; const double slowHz = 2;
        FramesUntil(slow, ref ts, slowHz, 60, -99, max: 20);
        int slowRise = FramesUntil(slow, ref ts, slowHz, 70, 70, max: 12);
        if (slowRise < 0) throw new InvalidOperationException("a steady rise read twice a second is never shown");
        // Review R9: frames where the icon is found but neither the digits nor the ring give a number are not
        // evidence for a rise and cannot complete it.
        var mute = new SelfHealthFilter(); double tm = 0;
        FramesUntil(mute, ref tm, hz, 60, -99, max: 40);
        for (int i = 0; i < straight - 1; i++, tm += 1 / hz) mute.Step(Sample(tm, 70), hz);
        for (int i = 0; i < 6; i++, tm += 1 / hz)
        {
            var s = new HudHealthSample { T = tm, State = "no_ring", Score = 0.8f, Cx = 557, Cy = 287, PctScore = 0.2f };
            mute.Step(s, hz);
            AssertEqual(60, s.Display, "a located frame with no number does not complete a rise");
        }
        // Review R10: the digit evidence for a rise is the filter's own reading of the digits (with the tens-blank
        // correction at high health), not the raw per-slot maximum. Bright background (no ring), the units read 4,
        // the tens slot is a close call between blank and 6: the raw value is 4, the filter reads 64.
        var close = new SelfHealthFilter(); double tq = 0;
        FramesUntil(close, ref tq, hz, 60, -99, max: 40);
        int closeRise = -1;
        for (int i = 0; i < 24 && closeRise < 0; i++, tq += 1 / hz)
        {
            var s = new HudHealthSample { T = tq, State = "ok", Score = 0.8f, Cx = 557, Cy = 287, PctScore = 0.9f, RingUnreliable = true, CnnRaw = 4 };
            var u = Enumerable.Repeat(0.005f, 11).ToArray(); u[4] = 0.95f; s.Probs[0] = u;
            var tens = Enumerable.Repeat(0.005f, 11).ToArray(); tens[10] = 0.5f; tens[6] = 0.45f; s.Probs[1] = tens;
            var h = Enumerable.Repeat(0.005f, 11).ToArray(); h[10] = 0.95f; s.Probs[2] = h;
            close.Step(s, hz);
            if (s.Display == 64) closeRise = i;
        }
        if (closeRise < 0) throw new InvalidOperationException("a rise the filter reads from corrected digits is never shown");
        // A real rise whose readings wobble between neighbours (79, 80, 79, ...): waiting for one value to stay put
        // would never show it; the readings stay above the display, so it is shown after SettleUp.
        f = new SelfHealthFilter(); t = 0;
        FramesUntil(f, ref t, hz, 50, -99, max: 40);
        int wobble = -1;
        for (int i = 0; i < 24; i++, t += 1 / hz)
        {
            var s = Sample(t, i % 2 == 0 ? 80 : 79, ring: 80); f.Step(s, hz);
            if (wobble < 0 && s.Display is 79 or 80) wobble = i;
        }
        if (wobble < 0 || wobble > 10) throw new InvalidOperationException($"a wobbling rise is shown late: {wobble}");
        int lagMax = wobble;
        Console.WriteLine($"PASS own health rises wait longer than drops (drop {drop}, rise {rise}, back {back} frames; wobbling rise {lagMax} frames)");
    }

    // 11-12 live test: while suffocating the plus sign is replaced by another icon (an arrow over three
    // lines), so the plus templates no longer find the health icon. The model may carry templates of
    // that icon. It must only win with a strong match (it scores 0.5-0.58 on plain texture), and a hit
    // needs a percent sign and a valid number below it. Synthetic pixels only.
    static HudPanelFrame AltPanel(bool glyph, double size = 1.0)
    {
        var f = new HudPanelFrame(); var rng = new Random(11);
        for (int i = 0; i < f.Bgr.Length; i += 3) { byte g = (byte)(20 + rng.Next(20)); f.Bgr[i] = (byte)(g + 8); f.Bgr[i + 1] = g; f.Bgr[i + 2] = g; }
        if (!glyph) return f;
        void Px(int x, int y) { int i = (y * HudPanelFrame.W + x) * 3; f.Bgr[i] = 255; f.Bgr[i + 1] = 230; f.Bgr[i + 2] = 160; }
        int cx = 300, cy = 250; int S(double v) => (int)Math.Round(v * size);
        for (int y = cy - S(14); y <= cy - S(2); y++) for (int x = cx - 2; x <= cx + 2; x++) Px(x, y);            // arrow shaft
        for (int k = 0; k <= S(6); k++) for (int x = cx - S(6) + k; x <= cx + S(6) - k; x++) Px(x, cy - S(4) + k); // arrow head
        foreach (int dy in new[] { S(5), S(9), S(13) })                                                               // three lines
            for (int y = cy + dy - 1; y <= cy + dy + 1; y++) for (int x = cx - S(15); x <= cx + S(15); x++) Px(x, y);
        return f;
    }

    static (string, int[], float[])[] AltBlocks()
    {
        var blocks = new List<(string, int[], float[])>();
        double[] sizes = { 0.92, 1.0, 1.08 };
        for (int i = 0; i < 3; i++)
        {
            int n = (int)Math.Round(34 * sizes[i]);
            var e = HudImageOps.EdgeRegion(AltPanel(true, sizes[i]), 300 - n / 2, 250 - n / 2, n, n);
            // EdgeRegion returns a reused buffer (11-13 performance fix): keep a copy of exactly n x n
            blocks.Add(($"alt.{i}", new[] { n, n }, e[..(n * n)]));
        }
        return blocks.ToArray();
    }

    static void AlternateIconNeedsAStrongMatch()
    {
        var m = HudHealthModel.Load(new MemoryStream(SyntheticModelBytes(AltBlocks())));
        AssertEqual(3, m.Alt.Count, "three alternate sizes");
        var loc = new HudIconLocator(m);
        var hit = loc.Find(AltPanel(true), 0);
        if (!loc.LastAlt || hit.score < 0.7f || Math.Abs(hit.cx - 300) > 2 || Math.Abs(hit.cy - 250) > 2)
            throw new InvalidOperationException($"alternate icon not found: alt={loc.LastAlt} {hit}");
        var strict = new HudIconLocator(m) { AltMin = 1.01f };
        strict.Find(AltPanel(true), 0);
        AssertEqual(false, strict.LastAlt, "below the alternate threshold the icon is not taken");
        var plain = new HudIconLocator(m);
        plain.Find(AltPanel(false), 0);
        AssertEqual(false, plain.LastAlt, "plain texture is not taken for the alternate icon");
        var none = new HudIconLocator(SyntheticModel());
        none.Find(AltPanel(true), 0);
        AssertEqual(false, none.LastAlt, "a model without alternate templates never reports one");
        Console.WriteLine("PASS own health alternate (suffocation) icon is found only with a strong match");
    }

    static void AlternateIconWithoutAReadingIsRejected()
    {
        var rec = new HudHealthRecognizer(HudHealthModel.Load(new MemoryStream(SyntheticModelBytes(AltBlocks()))));
        var r = rec.Process(AltPanel(true), 0, 8);
        AssertEqual("not_found", r.State, "an alternate icon with no percent reading below is not used");
        AssertEqual(null, r.RingEst, "no ring reading is kept");
        const BindingFlags any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        AssertEqual(-1.0, (double)typeof(HudIconLocator).GetField("homeCx", any)!.GetValue(rec.Loc)!, "the remembered position goes back");
        AssertEqual(false, rec.Loc.LastAlt, "the alternate flag is cleared");
        Console.WriteLine("PASS own health alternate icon without a percent reading is rejected and the position restored");
    }

    static void AlternateTemplatesAreOptionalButComplete()
    {
        AssertEqual(0, SyntheticModel().Alt.Count, "no alternate templates without the blocks");
        for (int miss = 0; miss < 3; miss++)
        {
            var rest = AltBlocks().Where((_, i) => i != miss).ToArray();
            ExpectInvalid(SyntheticModelBytes(rest), $"alternate templates without alt.{miss} are rejected");
        }
        var bad = AltBlocks(); bad[1] = ("alt.1", new[] { 4, 4 }, new float[16]);
        ExpectInvalid(SyntheticModelBytes(bad), "a tiny alternate template is rejected");
        Console.WriteLine("PASS own health alternate templates are optional, and complete when present");
    }

    // The success path (review R8): the state after a real match (display 5, a remembered position, the time of
    // the match) is set directly; the icon is gone and the digits under the remembered position read 0 (the
    // synthetic CNN has zero weights, so every slot reads 0). Readings are taken in place until 8 s after the last
    // real match, then stop; Reset clears the position.
    static void InPlaceReadsUntilTheWindowEnds()
    {
        const double hz = 8;
        var m = SyntheticModel();
        var rec = new HudHealthRecognizer(m);
        rec.Loc.FullSearchMinInterval = 1e12; rec.Loc.UseColour = false;
        double t = 0;
        for (int i = 0; i < 40; i++, t += 1 / hz) rec.Filter.Step(Sample(t, 5), hz);
        AssertEqual<int?>(5, rec.Filter.Shown, "the display shows 5");
        // A flat frame with the synthetic percent sign drawn where the digit band of an icon at (300, 200) is.
        var f = new HudPanelFrame();
        for (int i = 0; i < f.Bgr.Length; i++) f.Bgr[i] = 30;
        var pct = m.Pct[0];
        for (int y = 0; y < pct.H; y++)
            for (int x = 0; x < pct.W; x++)
            {
                int j = ((200 + 36 + 6 + y) * HudPanelFrame.W + 300 - 46 + 50 + x) * 3; byte v = (byte)pct.Data[y * pct.W + x];
                f.Bgr[j] = v; f.Bgr[j + 1] = v; f.Bgr[j + 2] = v;
            }
        const BindingFlags any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        typeof(HudIconLocator).GetField("homeCx", any)!.SetValue(rec.Loc, 300.0);
        typeof(HudIconLocator).GetField("homeCy", any)!.SetValue(rec.Loc, 200.0);
        typeof(HudHealthRecognizer).GetField("lastLockT", any)!.SetValue(rec, t);
        double lock0 = t; int inPlace = 0, after = 0;
        for (int i = 0; i < 80; i++, t += 1 / hz)
        {
            var r = rec.Process(f, t, hz);
            if (t - lock0 <= 7.9)
            {
                if (!r.InPlace || r.CnnRaw != 0 || r.Score != 0.6f) throw new InvalidOperationException($"no in-place reading at {t - lock0:0.00} s: state {r.State}, raw {r.CnnRaw}, pct {r.PctScore:0.00}");
                inPlace++;
            }
            else if (t - lock0 > 8.01) { AssertEqual(false, r.InPlace, "no in-place reading 8 s after the last real match"); after++; }
        }
        if (inPlace < 60 || after < 10) throw new InvalidOperationException($"window not exercised: {inPlace} in place, {after} after");
        // Reset forgets the position: put the display and the last match back, leave the position cleared.
        rec.Reset();
        for (int i = 0; i < 40; i++, t += 1 / hz) rec.Filter.Step(Sample(t, 5), hz);
        typeof(HudHealthRecognizer).GetField("lastLockT", any)!.SetValue(rec, t);
        AssertEqual(-1.0, (double)typeof(HudIconLocator).GetField("homeCx", any)!.GetValue(rec.Loc)!, "Reset clears the position");
        AssertEqual(false, rec.Process(f, t, hz).InPlace, "after Reset there is no remembered position to read");
        InPlaceFramesReachTheDisplay(f);
    }

    // The in-place readings go through the filter like any other reading (review R9). The synthetic CNN here
    // has a final bias that makes every slot read "0" with certainty; the filter then moves away from 5.
    static void InPlaceFramesReachTheDisplay(HudPanelFrame f)
    {
        const double hz = 8;
        var bias = new float[11]; bias[0] = 12f;
        var rec = new HudHealthRecognizer(HudHealthModel.Load(new MemoryStream(SyntheticModelBytes(("cnn.f.13.bias", new[] { 11 }, bias)))));
        rec.Loc.FullSearchMinInterval = 1e12; rec.Loc.UseColour = false;
        double t = 0;
        for (int i = 0; i < 40; i++, t += 1 / hz) rec.Filter.Step(Sample(t, 5), hz);
        const BindingFlags any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        typeof(HudIconLocator).GetField("homeCx", any)!.SetValue(rec.Loc, 300.0);
        typeof(HudIconLocator).GetField("homeCy", any)!.SetValue(rec.Loc, 200.0);
        typeof(HudHealthRecognizer).GetField("lastLockT", any)!.SetValue(rec, t);
        int inPlace = 0; int? last = 5; bool moved = false;
        for (int i = 0; i < 48 && !moved; i++, t += 1 / hz)
        {
            var r = rec.Process(f, t, hz);
            if (r.InPlace) inPlace++;
            if (r.Display is int d && d != 5) { moved = true; last = d; }
        }
        if (inPlace == 0 || !moved) throw new InvalidOperationException($"in-place readings did not reach the display: {inPlace} in place, display {last}");
    }

    // Bleeding: the plus sign and a blood drop take turns in the same place. When the icon is not found,
    // the digits under the last position are still read, but only below full health (a full-health icon
    // folds away and another one may take its place), within 8 s of a real match, and within 10 of the display.
    static void InPlaceReadingOnlyWhileBleedingIsPlausible()
    {
        AssertEqual(true, HudHealthRecognizer.InPlaceEligible(63, 2.0, 8.0), "bleeding at 63, matched 2 s ago");
        AssertEqual(false, HudHealthRecognizer.InPlaceEligible(null, 2.0, 8.0), "nothing shown yet");
        AssertEqual(false, HudHealthRecognizer.InPlaceEligible(99, 2.0, 8.0), "full health: the icon may have folded away");
        AssertEqual(false, HudHealthRecognizer.InPlaceEligible(63, 8.5, 8.0), "no real match for too long");
        AssertEqual(true, HudHealthRecognizer.InPlaceAccept(63, 57, 10), "a nearby reading is taken");
        AssertEqual(false, HudHealthRecognizer.InPlaceAccept(63, 94, 10), "a far reading (another icon's percent) is not");
        AssertEqual(false, HudHealthRecognizer.InPlaceAccept(63, null, 10), "no reading");
        InPlaceReadsUntilTheWindowEnds();
        // A recognizer that never matched anything never reads in place.
        var rec = new HudHealthRecognizer(SyntheticModel());
        var r = rec.Process(AltPanel(false), 0, 8);
        AssertEqual("not_found", r.State, "nothing to read on plain texture");
        AssertEqual(false, r.InPlace, "no in-place reading without a remembered position");
        Console.WriteLine("PASS own health in-place reading while bleeding needs a recent match, below full health, near the display");
    }

    // R4 review: dark scene at full health, then a bright floor where the ring is not trusted and the digits say 62.
    // The ring readings from the dark frames must not pull the display back or block the big change.
    static void StaleRingDoesNotHoldDigitsOnBrightBackground()
    {
        var f = new SelfHealthFilter(); const double hz = 8; double t = 0; int? shown = null;
        for (int i = 0; i < 24; i++, t += 1 / hz) { var s = Sample(t, 100, ring: 100); f.Step(s, hz); shown = s.Display; }
        AssertEqual(100, shown, "full health shown in the dark");
        int framesTo62 = -1;
        for (int i = 0; i < 16; i++, t += 1 / hz)
        {
            var s = Sample(t, 62); s.RingEst = null; s.ArcDeg = -1; s.State = "no_ring"; s.RingUnreliable = true;
            f.Step(s, hz);
            if (s.Display == 62 && framesTo62 < 0) framesTo62 = i;
        }
        if (framesTo62 < 0 || framesTo62 > 8) throw new InvalidOperationException($"bright floor: digits 62 shown after {framesTo62} frames");
        Console.WriteLine("PASS own health stale ring readings do not hold the digits on a bright background");
    }

    static void DisplayFollowsDigitsAndIgnoresGlitches()
    {
        var f = new SelfHealthFilter();
        const double hz = 8;
        double t = 0;
        int? Step(HudHealthSample s) { f.Step(s, hz); return s.Display; }
        int? shown = null;
        for (int i = 0; i < 16; i++, t += 1 / hz) shown = Step(Sample(t, 78));
        AssertEqual(78, shown, "steady 78 is shown");
        // A visor glitch hides the tens digit for a few frames: the ring still says ~78.
        for (int i = 0; i < 3; i++, t += 1 / hz)
        {
            var g = Sample(t, 8, ring: 78);
            AssertEqual(78, Step(g), "a short single-digit glitch does not change the display");
        }
        for (int i = 0; i < 4; i++, t += 1 / hz) shown = Step(Sample(t, 78));
        // Taking damage: the reading drops to 41 and stays there.
        int framesTo41 = -1;
        for (int i = 0; i < 16; i++, t += 1 / hz)
        {
            shown = Step(Sample(t, 41));
            if (shown == 41 && framesTo41 < 0) framesTo41 = i;
        }
        AssertEqual(41, shown, "damage to 41 is shown");
        if (framesTo41 > 6) throw new InvalidOperationException($"damage shown too late: {framesTo41} frames");
        // Black screen (death, loading) for more than half a second clears the value.
        HudHealthSample last = Sample(t, 41);
        for (int i = 0; i < 6; i++, t += 1 / hz) { last = new HudHealthSample { T = t, State = "black" }; f.Step(last, hz); }
        AssertEqual<int?>(null, last.Display, "black screen clears the value");
        AssertEqual("黑屏", last.Note, "black screen note");
        Console.WriteLine("PASS own health display follows digits, ignores short glitches and clears on black");
    }

    // ---- lifecycle -----------------------------------------------------------------------

    sealed class FakeSource : IHudFrameSource
    {
        public bool Disposed; public int Captures;
        public bool TryCapture(HudPanelFrame frame) { Captures++; return true; }
        public void Dispose() => Disposed = true;
    }

    sealed class FakeFactory : IHudFrameSourceFactory
    {
        public readonly List<FakeSource> Made = new();
        public bool Fail;
        public IHudFrameSource? TryCreate() { if (Fail) return null; var s = new FakeSource(); Made.Add(s); return s; }
    }

    static void LifecycleCapturesOnlyWhenAllowedAndReleasesEverything()
    {
        bool enabled = false, running = true, foreground = true;
        var factory = new FakeFactory();
        var published = new List<SelfHealthReading>();
        var service = new SelfHealthReadingService(() => enabled, () => running, () => foreground,
            SyntheticModel, factory, published.Add);
        double t = 0;
        for (int i = 0; i < 3; i++) service.Step(t += 0.125);
        AssertEqual(0, factory.Made.Count, "switch off (the default): nothing is captured");

        enabled = true;
        for (int i = 0; i < 3; i++) service.Step(t += 0.125);
        AssertEqual(1, factory.Made.Count, "switch on, game running and in front: one capture source");
        AssertEqual(true, factory.Made[0].Captures >= 3, "frames are read");

        foreground = false;
        service.Step(t += 0.125);
        AssertEqual(true, factory.Made[0].Disposed, "game window not in front: capture released");
        AssertEqual(false, service.Capturing, "not capturing while another window is in front");
        AssertEqual(SelfHealthReading.None, service.LastReading, "visor gets no reading (no ring)");

        foreground = true;
        service.Step(t += 0.125);
        AssertEqual(2, factory.Made.Count, "back in front: a new source");
        running = false;
        service.Step(t += 0.125);
        AssertEqual(true, factory.Made[1].Disposed, "game exit: capture released");

        running = true;
        service.Step(t += 0.125);
        enabled = false;
        service.Step(t += 0.125);
        AssertEqual(true, factory.Made[2].Disposed, "switch off: capture released");

        enabled = true;
        service.Step(t += 0.125);
        service.Dispose();
        AssertEqual(true, factory.Made.All(s => s.Disposed), "dispose releases every source");
        AssertEqual(service.SourcesCreated, service.SourcesDisposed, "every created source is disposed");
        Console.WriteLine("PASS own health captures only when switched on, running and in front, and releases everything");
    }

    sealed class ScriptedSource : IHudFrameSource
    {
        public bool Capture = true, New = true, Lost, Disposed;
        public bool TryCapture(HudPanelFrame frame) => Capture;
        public bool LastFrameWasNew => New;
        public bool TargetLost => Lost;
        public void Dispose() => Disposed = true;
    }

    sealed class ScriptedFactory : IHudFrameSourceFactory
    {
        public readonly List<ScriptedSource> Made = new();
        public IHudFrameSource? TryCreate() { var s = new ScriptedSource(); Made.Add(s); return s; }
    }

    // Background reading (11-13): only new images keep the ring up (no new image for over 2 seconds: no reading,
    // even while the previous image stands in), and a capture whose window is no longer the one to read is
    // released and replaced (review CX-HUD-HEALTH-BG-073 P2/P3).
    static void OnlyNewImagesKeepTheRingAndALostWindowIsReplaced()
    {
        var factory = new ScriptedFactory();
        // The life-state seam gives every read image a reading, so "no reading" can only come from the rules.
        var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, factory, _ => { },
            lifeState: () => SelfHealthState.Dead);
        double t = 0.125;
        service.Step(t);
        AssertEqual(SelfHealthState.Dead, service.LastReading.State, "a new image gives a reading");
        var first = factory.Made[0];
        first.New = false;
        // 16 stand-in reads: the last one is exactly 2 seconds after the new image, not over 2 seconds
        for (int i = 0; i < 16; i++) service.Step(t += 0.125);
        AssertEqual(SelfHealthState.Dead, service.LastReading.State, "stand-in images within 2 seconds keep the reading");
        service.Step(t += 0.125);
        AssertEqual(SelfHealthReading.None, service.LastReading, "no new image for over 2 seconds: no reading");
        first.New = true;
        service.Step(t += 0.125);
        AssertEqual(SelfHealthState.Dead, service.LastReading.State, "a new image brings the reading back");

        first.Capture = false; first.Lost = true;
        service.Step(t += 0.125);
        AssertEqual(true, first.Disposed, "a lost window's capture is released");
        AssertEqual(false, service.Capturing, "nothing is captured until the current window is picked up");
        AssertEqual(SelfHealthReading.None, service.LastReading, "lost window: no reading");
        service.Step(t += 0.125);
        AssertEqual(2, factory.Made.Count, "the next read starts a capture of the current window");
        AssertEqual(SelfHealthState.Dead, service.LastReading.State, "and reads it");
        service.Dispose();
        AssertEqual(service.SourcesCreated, service.SourcesDisposed, "every created source is disposed");
        Console.WriteLine("PASS own health only new images keep the ring; a lost window's capture is replaced");
    }

    // ---- full health (11-13 user: "我满血时游戏里也不会显示血量圈"; "一起吧"; "继续修"; "甲";
    //      "刚进游戏如果没有显示血量也一定是满血") ------------------------------------------------------------------
    // Rule after review rounds 1-13: the screen sets "full" (two clear full readings in a row, or no tile in a new life
    // that was watched unbroken); log events only clear it or mark a new life; an injured reading locks out any full.

    static SelfHealthLife Life(long revision = 1, SelfHealthPresence presence = SelfHealthPresence.InUniverse, bool dead = false,
        long lifeStart = 0, bool newLife = false, long joins = 0) => new(presence, dead, revision, lifeStart, newLife, joins);

    static void FullHoldFollowsClearDigitsOnly()
    {
        var hold = new SelfHealthFullHold();
        var life = Life();
        double now = 0;
        int? Next(int? display, int? digits = null, bool tile = false, bool fresh = true, bool black = false, bool? evidence = null,
            double? ring = null, bool continuous = true)
        {
            now += 0.125;
            return hold.Next(display, evidence ?? (display != null || digits != null || ring != null), tile || display != null || digits != null || ring != null,
                black, fresh, digits, life, now, continuous, ring);
        }
        void ReadFull() { Next(100, digits: 100); Next(100, digits: 100); }

        AssertEqual<int?>(null, Next(null), "nothing read yet: no ring");
        AssertEqual<int?>(100, Next(100, digits: 100), "a full reading goes through");
        AssertEqual<int?>(null, Next(null), "one full reading is not enough to remember (a digit misread)");
        ReadFull();
        AssertEqual<int?>(100, Next(null), "two full readings in a row, the tile folded away: full");
        AssertEqual(SelfHealthHoldOutcome.Held, hold.Last, "kept from memory");
        AssertEqual<int?>(null, Next(null, black: true), "black screen: no ring");
        AssertEqual<int?>(100, Next(null), "after a black screen with no event the memory is still there");
        AssertEqual<int?>(100, Next(null, continuous: false), "a gap (switched away and back) with no event keeps it (user '甲')");

        // Injured lock (round 12/13 P1): once an image reads below full, no full value is shown in any way.
        AssertEqual<int?>(null, Next(100, digits: 70), "digits 70 under a smoothed 100: no ring");
        AssertEqual<int?>(null, Next(100, ring: 100), "next image ring only, smoothed 100: still no full ring");
        AssertEqual<int?>(null, Next(100, evidence: false), "a carried 100 with no tile: no full ring");
        AssertEqual<int?>(null, Next(null), "no tile: no full ring from memory");
        AssertEqual<int?>(80, Next(80, digits: 80), "a lower value is shown");
        AssertEqual<int?>(null, Next(100, digits: 100), "one full reading does not lift the lock");
        AssertEqual<int?>(100, Next(100, digits: 100), "a second one in a row does");
        AssertEqual<int?>(100, Next(null), "and full is remembered");
        // Full readings must come in a row (round 14 P1): anything in between starts the count again.
        Next(80, digits: 80);
        Next(100, digits: 100);
        Next(100, ring: 100);
        AssertEqual<int?>(null, Next(100, digits: 100), "full digits, a ring-only image, full digits: still locked");
        Next(null, black: true);
        AssertEqual<int?>(null, Next(100, digits: 100), "full digits after a black screen: still locked");
        Next(null, continuous: false);
        AssertEqual<int?>(null, Next(100, digits: 100), "full digits after a gap: still locked");
        AssertEqual<int?>(100, Next(100, digits: 100), "two in a row: unlocked");
        // Ring only: a clearly low ring locks (round 13 P2); a ring at full keeps an earlier full; a ring a little low
        // drops the memory but does not lock.
        AssertEqual<int?>(null, Next(100, ring: 70), "ring only reads 70 under a smoothed 100: no ring");
        AssertEqual<int?>(null, Next(null), "locked");
        ReadFull();
        AssertEqual<int?>(100, Next(100, ring: 100), "ring at full");
        AssertEqual<int?>(100, Next(null), "keeps the earlier full");
        AssertEqual<int?>(95, Next(95, ring: 95), "ring only at 95 is shown");
        AssertEqual<int?>(null, Next(null), "and the memory is dropped (only clear digits bring it back)");

        // Carried values and stale images never touch the memory.
        ReadFull();
        AssertEqual<int?>(null, Next(100, evidence: false, tile: true), "a carried full on a tile on screen: no ring");
        AssertEqual<int?>(70, Next(70, evidence: false, tile: true), "a carried lower value: shown for the short smoothing");
        AssertEqual<int?>(100, Next(null), "and the memory is untouched");
        AssertEqual<int?>(80, Next(80, digits: 80, fresh: false), "an old image is shown like a carried value");
        AssertEqual<int?>(100, Next(null), "and does not clear the memory");
        AssertEqual<int?>(null, Next(null, tile: true), "the tile on screen but unread: no ring");

        // The log only clears (and lifts the injured lock: a death starts a new, unhurt life).
        life = Life(2);
        AssertEqual<int?>(null, Next(null), "a health event clears it");
        ReadFull();
        life = Life(3);
        AssertEqual<int?>(null, Next(null, black: true), "an event during a black screen");
        AssertEqual<int?>(null, Next(null), "is taken in: cleared");
        ReadFull();
        life = Life(3, dead: true);
        AssertEqual<int?>(null, Next(100, digits: 100), "dead: no ring, whatever the image gives");
        life = Life(4, presence: SelfHealthPresence.Away);
        AssertEqual<int?>(null, Next(100, digits: 100), "away: no ring");
        ReadFull();
        hold.Forget(Life(4));
        life = Life(4);
        AssertEqual<int?>(null, Next(null), "forgotten when the switch goes off or the game closes");
        Console.WriteLine("PASS own health full memory: clear full readings set it, injured readings lock it, health events clear it");
    }

    // 11-17 user ("我们日志检测有进服识别", replacing the 11-13 rule that needed unbroken watching and no tile for 2 s): a
    // new life the log began while the hold was watching is full at once, with the tile folded away or found but not read;
    // a reading below full, a health event or the switch going off ends it; only where clear digits were read at this
    // capture size; never for a life that began before the hold was watching, and never without a join or respawn line.
    static void NewLifeFromTheLogIsFull()
    {
        var hold = new SelfHealthFullHold();
        SelfHealthLife life = Life(1);
        double now = 0;
        int? Next(int? display = null, int? digits = null, bool tile = false, bool black = false, bool readable = true, double? ring = null,
            bool continuous = true, double step = 0.125)
        {
            now += step;
            return hold.Next(display, display != null || digits != null || ring != null, tile || display != null || digits != null || ring != null,
                black, true, digits, life, now, continuous, ring, readable);
        }
        // The hold watching; the player joins a server (away while loading); the spawn line is next.
        void Begin()
        {
            hold = new SelfHealthFullHold(); now = 0;
            life = Life(1); Next();
            life = Life(2, SelfHealthPresence.Away); Next();
            life = Life(2, lifeStart: 1, newLife: true);
        }
        int? r = null;

        Begin();
        AssertEqual<int?>(100, Next(), "the spawn after a join: full at once, the tile folded away");
        AssertEqual(SelfHealthHoldOutcome.NewLifeFull, hold.Last, "by the new-life rule");
        AssertEqual<int?>(100, Next(tile: true), "a tile found but not read does not end it");
        AssertEqual(SelfHealthHoldOutcome.NewLifeFull, hold.Last, "still the new-life rule");
        AssertEqual<int?>(null, Next(black: true), "a black image shows nothing");
        AssertEqual<int?>(100, Next(), "after it, full again");
        AssertEqual<int?>(100, Next(continuous: false), "a gap (switched away) does not end it");
        AssertEqual<int?>(100, Next(100, digits: 100), "a full reading goes on showing 100");
        AssertEqual<int?>(100, Next(tile: true), "still the new life: an unread tile still shows 100");
        AssertEqual<int?>(70, Next(70, digits: 70), "a reading below full shows the reading");
        AssertEqual(true, hold.Injured, "and locks out full");
        AssertEqual(false, hold.NewLife, "the new life is over");
        AssertEqual<int?>(null, Next(), "no full after it");
        AssertEqual<int?>(null, Next(tile: true), "nor with the tile unread");

        // A clearly low ring ends it with the lock; a ring-only value below full ends it without the lock.
        Begin();
        Next();
        AssertEqual<int?>(null, Next(ring: 60), "a clearly low ring and no value yet: no ring");
        AssertEqual(true, hold.Injured, "a clearly low ring locks out full");
        AssertEqual<int?>(null, Next(), "and ends the new life");
        Begin();
        AssertEqual<int?>(95, Next(95, ring: 95), "a ring-only value below full is shown");
        AssertEqual(false, hold.Injured, "without the lock");
        AssertEqual<int?>(null, Next(), "and the new life is over");

        // Health events end it at once and it does not come back without a new life.
        foreach (var (name, after) in new (string, SelfHealthLife)[]
        {
            ("downed or revived", Life(3, lifeStart: 1)),
            ("dead", Life(3, dead: true, lifeStart: 1)),
            ("left the server", Life(3, SelfHealthPresence.Away, lifeStart: 1)),
            ("the game started or stopped", Life(3, SelfHealthPresence.Unknown, lifeStart: 1)),
        })
        {
            Begin();
            AssertEqual<int?>(100, Next(), $"{name}: full before");
            life = after;
            AssertEqual<int?>(null, Next(), $"{name}: ends at once");
            life = after with { Presence = SelfHealthPresence.InUniverse, Dead = false };
            AssertEqual<int?>(null, Next(), $"{name}: does not come back without a new life");
        }

        // A respawn is a new life too, also with the death taken in at the same time; a new life a later event already
        // closed is not.
        Begin();
        Next();
        life = Life(3, dead: true, lifeStart: 1); Next();
        life = Life(3, lifeStart: 2, newLife: true);
        AssertEqual<int?>(100, Next(), "a respawn after a death: full at once");
        Begin();
        Next();
        life = Life(4, lifeStart: 2, newLife: true);
        AssertEqual<int?>(100, Next(), "a death and respawn taken in together: full too");
        Begin();
        life = Life(3, lifeStart: 1, newLife: false);
        AssertEqual<int?>(null, Next(), "a new life a later event closed (taken in together): no full");
        // A respawn line with no death before it does not lift an injured lock (the line can come late, after the new
        // life was already seen hurt).
        Begin();
        Next(70, digits: 70);
        life = Life(2, lifeStart: 2, newLife: true);
        AssertEqual<int?>(null, Next(), "a respawn alone does not lift the injured lock");

        // Review R1 P1: a death and respawn that come late together, under 10 s after the new life was seen hurt: no full.
        Begin();
        Next();
        Next(70, digits: 70);
        life = Life(4, lifeStart: 2, newLife: true);
        AssertEqual<int?>(null, Next(), "a late death and respawn under 10 s after a reading below full: no full");
        AssertEqual(false, hold.NewLife, "no new life");
        for (int i = 0; i < 80; i++) Next();
        life = Life(5, dead: true, lifeStart: 2); Next();
        life = Life(5, lifeStart: 3, newLife: true);
        AssertEqual<int?>(100, Next(), "a respawn over 10 s after it: full");
        Begin();
        Next();
        AssertEqual<int?>(95, Next(95, ring: 95), "a ring-only value below full");
        life = Life(4, lifeStart: 2, newLife: true);
        AssertEqual<int?>(null, Next(), "a late death and respawn soon after a ring-only value below full: no full either");
        // Review R2 P1: time switched away (no images, so no facts taken in) does not count toward the 10 s.
        Begin();
        Next();
        Next(70, digits: 70);
        Next(continuous: false, step: 11);
        life = Life(4, lifeStart: 2, newLife: true);
        AssertEqual<int?>(null, Next(), "11 s switched away after a reading below full, then a late death and respawn: no full");
        // Review R3 P1: joining hurt: the screen reads 70 before the spawn line comes (the log still says away): no full.
        Begin();
        life = Life(2, SelfHealthPresence.Away);
        Next(70, digits: 70);
        life = Life(2, lifeStart: 1, newLife: true);
        AssertEqual<int?>(null, Next(tile: true), "a reading below full while still away, then the spawn line: no full");
        AssertEqual<int?>(null, Next(), "nor with the tile folded");
        // Review R4 P1: the new server read hurt before its join and spawn lines come together: no full.
        hold = new SelfHealthFullHold(); now = 0;
        life = Life(1); Next();
        Next(70, digits: 70);
        life = Life(2, lifeStart: 1, newLife: true, joins: 1);
        AssertEqual<int?>(null, Next(tile: true), "a reading below full, then a late join and spawn together: no full");
        AssertEqual<int?>(null, Next(), "nor with the tile folded");
        // Review R4 P2: a join while the switch was off: the previous server's injured lock is not carried into it.
        hold = new SelfHealthFullHold(); now = 0;
        life = Life(1); Next();
        Next(70, digits: 70);
        AssertEqual(true, hold.Injured, "hurt on the previous server");
        hold.Forget(Life(3, SelfHealthPresence.Away, joins: 1));
        life = Life(3, lifeStart: 1, newLife: true, joins: 1);
        AssertEqual<int?>(100, Next(continuous: false, step: 30), "switched on while loading the next server, then the spawn: full");
        // Review R4 P1: healed to full, the tile folds away, the smoothing still carries 98: shown under 1 s at most.
        hold = new SelfHealthFullHold(); now = 0;
        life = Life(1); Next();
        Next(98, digits: 98);
        int? Carried() { now += 0.125; return hold.Next(98, false, false, false, true, null, life, now, true, null, true); }
        AssertEqual<int?>(98, Carried(), "the carried value right after");
        for (int i = 0; i < 1; i++) Carried();
        AssertEqual<int?>(98, Carried(), "0.375 s after the tile's last image: still carried");
        AssertEqual(false, hold.DropKept, "nothing dropped yet");
        AssertEqual<int?>(null, Carried(), "0.5 s after the tile's last image: no longer carried (review R6 P1)");
        AssertEqual(true, hold.DropKept, "dropped on purpose: the short-gap keep must not put it back (review R5 P1)");
        // Review R3 P2: a server join forgets readings from before it (the previous session's injury).
        hold = new SelfHealthFullHold(); now = 0;
        life = Life(1); Next();
        Next(70, digits: 70);
        life = Life(2, SelfHealthPresence.Away, joins: 1);
        Next(continuous: false, step: 30);               // loading, switched away
        life = Life(2, lifeStart: 1, newLife: true, joins: 1);
        AssertEqual<int?>(100, Next(continuous: false, step: 30), "after a join, an earlier session's reading below full does not hold back the spawn");
        // Review R3 P2: a ring-only reading below full drops the full memory too.
        hold = new SelfHealthFullHold(); now = 0;
        life = Life(1); Next();
        Next(100, digits: 100); Next(100, digits: 100);
        AssertEqual(true, hold.Full, "full read");
        AssertEqual<int?>(null, Next(100, ring: 95), "a ring-only 95 under a smoothed 100: that image does not show full (review R4 P1)");
        AssertEqual(true, hold.DropKept, "and the short-gap keep must not put the 100 back (review R5 P1)");
        AssertEqual(false, hold.Full, "a ring-only 95 under a smoothed 100 drops the full memory");
        AssertEqual<int?>(null, Next(), "no full after it with the tile folded");
        // Review R6 P1: the smoothing still carries 100 (not marked folded) with the tile lost: not shown.
        now += 0.125;
        AssertEqual<int?>(null, hold.Next(100, false, false, false, true, null, life, now, true, null, true), "a carried 100 on its own: not shown");
        now += 0.125;
        AssertEqual<int?>(null, hold.Next(100, false, true, false, true, null, life, now, true, null, true), "nor with the tile on screen unread");
        // Review R2 P2: a ring-only reading below full ends the new life even while the smoothed value is still full.
        Begin();
        Next();
        AssertEqual<int?>(null, Next(100, ring: 95), "a ring-only 95 under a smoothed 100 in a new life: not full");
        AssertEqual(false, hold.NewLife, "a ring-only 95 under a smoothed 100 ends the new life");
        AssertEqual<int?>(null, Next(tile: true), "an unread tile after it shows nothing");
        // 99 or more in a new life is shown as 100 (no 100/99 wobble).
        Begin();
        AssertEqual<int?>(100, Next(99, digits: 99), "a reading of 99 in a new life is shown as 100");
        AssertEqual<int?>(100, Next(), "and full after it");
        Begin();
        AssertEqual<int?>(99, Next(99, digits: 99, readable: false), "not where the size was never read clearly (review R2 P2)");

        // Review R5 P1: the game log not being read (the log page stopped, the log unreadable) ends the new life, and none
        // begins while it is not read.
        Begin();
        AssertEqual<int?>(100, Next(), "full");
        int? Unlogged(bool tile = false) { now += 0.125; return hold.Next(null, false, tile, false, true, null, life, now, true, null, true, logLive: false); }
        AssertEqual<int?>(null, Unlogged(), "the log no longer read: the new life ends at once");
        AssertEqual<int?>(null, Next(), "and does not come back when it is read again");
        Begin();
        AssertEqual<int?>(null, Unlogged(), "a spawn taken in while the log is not read: no full");
        AssertEqual<int?>(null, Next(), "nor after");

        // Only where clear digits were read at this capture size.
        Begin();
        AssertEqual<int?>(null, Next(readable: false), "this capture size never read clearly: no full");
        AssertEqual(true, hold.NewLifeWaitingForSize, "counted as waiting for the size");
        AssertEqual<int?>(null, Next(tile: true, readable: false), "nor with an unread tile");
        AssertEqual(true, hold.NewLifeWaitingForSize, "waiting");
        AssertEqual<int?>(100, Next(), "read at this size: full");
        AssertEqual(false, hold.NewLifeWaitingForSize, "no longer waiting");

        // A life that began before the hold was watching: never (the reader started, or the switch came on, mid-life).
        hold = new SelfHealthFullHold(); now = 0;
        life = Life(2, lifeStart: 1, newLife: true);
        for (int i = 0; i < 20; i++) r = Next();
        AssertEqual<int?>(null, r, "the reader started in the middle of a new life: no full");
        Begin();
        AssertEqual<int?>(100, Next(), "full");
        hold.Forget(life);
        for (int i = 0; i < 20; i++) r = Next();
        AssertEqual<int?>(null, r, "the switch off and on in the new life: not full again");
        Begin();
        Next();
        hold.Forget();
        for (int i = 0; i < 20; i++) r = Next();
        AssertEqual<int?>(null, r, "forgotten without the facts: the next facts are taken as seen");

        // No join or respawn in the log (b100 15:33-15:36, or no log at all): never.
        hold = new SelfHealthFullHold(); now = 0;
        life = Life(0, SelfHealthPresence.Unknown);
        for (int i = 0; i < 20; i++) r = Next();
        life = Life(0, SelfHealthPresence.InUniverse);
        for (int i = 0; i < 20; i++) r = Next();
        AssertEqual<int?>(null, r, "no join or respawn line: no full");
        Console.WriteLine("PASS own health a new life the log began while watching is full until a reading below full or a health event");
    }

    // The recognizer's own "full, then the tile folded away" 100 is marked, so the reader treats it as "no tile".
    static void FilterMarksItsFoldedAwayFull()
    {
        const double hz = 8;
        var filter = new SelfHealthFilter();
        double t = 0;
        HudHealthSample last = Sample(0, 100);
        for (int i = 0; i < 24; i++, t += 1 / hz) { last = Sample(t, 100); filter.Step(last, hz); }
        AssertEqual<int?>(100, last.Display, "full is read");
        AssertEqual(false, last.FoldedFull, "a read value is not marked");
        AssertEqual<int?>(100, last.FrameDigits, "the digits of this image read 100");
        // a frame with no tile carries no digits or ring, as the recognizer leaves it
        for (int i = 0; i < 120; i++, t += 1 / hz) { last = new HudHealthSample { T = t, State = "not_found" }; filter.Step(last, hz); }
        AssertEqual<int?>(100, last.Display, "the tile folded away: the filter keeps 100");
        AssertEqual(true, last.FoldedFull, "and marks it as kept, not read");
        AssertEqual<int?>(null, last.FrameDigits, "no digits in an image without the tile");
        Console.WriteLine("PASS own health filter marks its folded-away full value and this image's own digits");
    }

    // The recognizer's smoothing, through to what the reader shows.
    static void CarriedValuesNeverRefreshTheMemory()
    {
        const double hz = 8;
        foreach (var value in new[] { 100, 70 })
        {
            var filter = new SelfHealthFilter();
            var hold = new SelfHealthFullHold();
            var life = Life();
            double t = 0;
            int? shown = null;
            HudHealthSample last = Sample(0, value);
            void Feed(HudHealthSample sample)
            {
                filter.Step(sample, hz);
                last = sample;
                var tile = sample.State is not ("black" or "not_found");
                shown = hold.Next(sample.FoldedFull ? null : sample.Display, sample.Evidence, tile, sample.State == "black", true,
                    sample.FrameDigits, life, t, true, sample.FrameRing);
                t += 1 / hz;
            }
            for (int i = 0; i < 24; i++) Feed(Sample(t, value));
            AssertEqual<int?>(value, shown, $"{value} is read");
            AssertEqual(true, last.Evidence, "a read value has evidence");
            // the tile is on screen (found at the same place), but neither digits nor ring can be read
            Feed(new HudHealthSample { T = t, State = "no_ring", Score = 0.8f, Cx = 557, Cy = 287 });
            AssertEqual(false, last.Evidence, "nothing was read from this image");
            AssertEqual<int?>(value, last.Display, "the recognizer carries the earlier value over");
            if (value == 100)
            {
                AssertEqual<int?>(null, shown, "a carried full on a tile that is shown: no ring (it is not folded away)");
                for (int i = 0; i < 120; i++) Feed(new HudHealthSample { T = t, State = "not_found" });
                AssertEqual<int?>(100, shown, "the tile folded away after clear full digits: full");
            }
            else
            {
                AssertEqual<int?>(70, shown, "a carried lower value is still shown for the short smoothing");
                for (int i = 0; i < 120; i++) Feed(new HudHealthSample { T = t, State = "not_found" });
                AssertEqual<int?>(null, shown, "no full ring after a lower value");
            }
        }
        Console.WriteLine("PASS own health carried values are shown briefly but never refresh the full memory");
    }

    // Facts are applied in arrival order; their times are not used; nothing is replayed.
    static void LifeContextFollowsTheGameLog()
    {
        using var context = new SelfHealthLifeContext(null);
        AssertEqual(SelfHealthPresence.Unknown, context.Current.Presence, "nothing yet: unknown");
        context.Apply("GameStarted");
        AssertEqual(SelfHealthPresence.Unknown, context.Current.Presence, "game started: unknown (also written when the Host starts late)");
        AssertEqual(0L, context.Current.Joins, "no join yet");
        context.Apply("ServerJoined");
        AssertEqual(SelfHealthPresence.Away, context.Current.Presence, "joined: not in the universe yet");
        AssertEqual(1L, context.Current.Joins, "a join is counted (11-17: the tile search starts afresh)");
        var revision = context.Current.Revision;
        context.Apply("PlayerLocationChanged");
        AssertEqual(SelfHealthPresence.InUniverse, context.Current.Presence, "a location: in the universe");
        AssertEqual(revision, context.Current.Revision, "a location says nothing about health");
        AssertEqual(1L, context.Current.LifeStart, "the first location after joining starts a new life");
        AssertEqual(true, context.Current.NewLifeOpen, "open until a health event");
        context.Apply("PlayerLocationChanged");
        AssertEqual(1L, context.Current.LifeStart, "moving on is not a new life");
        context.Apply("PlayerDowned");
        AssertEqual(revision + 1, context.Current.Revision, "downed may end full health");
        AssertEqual(false, context.Current.NewLifeOpen, "and closes the new life");
        context.Apply("PlayerDied");
        context.Apply("PlayerLocationChanged");
        AssertEqual(true, context.Current.Dead, "a later location does not bring a dead player back");
        AssertEqual(1L, context.Current.LifeStart, "nor start a new life");
        revision = context.Current.Revision;
        context.Apply("PlayerRespawned");
        AssertEqual(false, context.Current.Dead, "respawned: alive");
        AssertEqual(2L, context.Current.LifeStart, "a respawn starts a new life");
        AssertEqual(true, context.Current.NewLifeOpen, "open");
        AssertEqual(revision, context.Current.Revision, "a respawn does not clear full");
        context.Apply("PlayerRevived");
        AssertEqual(revision + 1, context.Current.Revision, "revived: health is low");
        AssertEqual(false, context.Current.NewLifeOpen, "closed");
        context.Apply("ServerLeft");
        AssertEqual(SelfHealthPresence.Away, context.Current.Presence, "left the server: away");
        context.Apply("GameStopped");
        AssertEqual(SelfHealthPresence.Away, context.Current.Presence, "game stopped: away");
        AssertEqual(1L, context.Current.Joins, "only joins count as joins");
        context.Apply("ServerJoined");
        AssertEqual(2L, context.Current.Joins, "each join counts");
        Console.WriteLine("PASS own health life facts follow the game log in arrival order (new lives, health events)");
    }

    // Late log lines can only make the ring more careful (review rounds 5, 10, 11).
    static void LateEventsOnlyEverClearFull()
    {
        using var context = new SelfHealthLifeContext(null);
        var hold = new SelfHealthFullHold();
        double now = 0;
        int? Look(int? display, int? digits) { now += 0.125; return hold.Next(display, digits != null, digits != null, false, true, digits, context.Current, now); }
        context.Apply("ServerJoined");
        context.Apply("PlayerLocationChanged");
        Look(100, 100);
        AssertEqual<int?>(100, Look(100, 100), "the spawn's tile reads 100");
        context.Apply("PlayerRespawned");   // its log line arrives after the tile was read
        AssertEqual<int?>(100, Look(null, null), "a respawn arriving after the spawn's 100%: still full");
        Look(70, 70);
        context.Apply("PlayerDied");
        context.Apply("PlayerRespawned");   // a death and respawn arriving together, late
        AssertEqual<int?>(null, Look(null, null), "a late death clears it (no ring rather than a wrong one)");
        for (int i = 0; i < 40; i++) Look(null, null);
        AssertEqual<int?>(null, Look(null, null), "the tile was seen just before: the new-life rule stays off");
        context.Apply("PlayerRespawned");   // only a respawn: no "full" from the log itself
        AssertEqual<int?>(null, Look(null, null), "a respawn alone never sets full at once");
        Look(100, 100);
        AssertEqual<int?>(100, Look(100, 100), "the screen reads full");
        AssertEqual<int?>(100, Look(null, null), "then kept");
        Console.WriteLine("PASS own health late log events only ever clear full; only the screen sets it");
    }

    sealed class GrayFactory : IHudFrameSourceFactory
    {
        public readonly List<GraySource> Made = new();
        public (int Width, int Height) Size;
        public IHudFrameSource? TryCreate() { var s = new GraySource { Size = Size }; Made.Add(s); return s; }
    }

    // A plain grey image: not black, and no health tile in it.
    sealed class GraySource : IHudFrameSource
    {
        public bool Disposed, Capture = true, New = true, Black;
        public bool TryCapture(HudPanelFrame frame) { if (!Capture) return false; Array.Fill(frame.Bgr, Black ? (byte)0 : (byte)60); return true; }
        public bool LastFrameWasNew => New;
        public (int Width, int Height) Size;
        // like the real capture: no size while no image is had
        public (int Width, int Height) CaptureSize => Capture ? Size : (0, 0);
        public void Dispose() => Disposed = true;
    }

    static void ServiceShowsFullWhenTheTileIsFoldedAndCountsWithoutValues()
    {
        var lines = new List<string>();
        bool enabled = true, front = true;
        var life = Life();
        var factory = new GrayFactory();
        var service = new SelfHealthReadingService(() => enabled, () => true, () => front, SyntheticModel, factory, _ => { })
        {
            Life = () => life,
            Diagnostics = new SelfHealthDiagnostics(lines.Add),
        };
        double t = 0;
        service.Step(t += 0.125);
        AssertEqual(SelfHealthReading.None, service.LastReading, "no tile and nothing read: no ring");
        service.Hold.RememberFullForTest();   // as if the tile had just read 100 (the synthetic model reads no digits)
        service.Step(t += 0.125);
        AssertEqual<int?>(100, service.LastReading.Percent, "full read before, no tile on screen: full ring");
        AssertEqual(SelfHealthState.Normal, service.LastReading.State, "shown as alive");

        front = false;
        service.Step(t += 0.125);
        AssertEqual(SelfHealthReading.None, service.LastReading, "switched away: no ring (capture stopped)");
        front = true;
        service.Step(t += 0.125);
        AssertEqual<int?>(100, service.LastReading.Percent, "back with no health event meanwhile: full again at once");

        enabled = false;
        service.Step(t += 0.125);
        service.Step(t += 0.125);   // an idle poll after the stop is the same stop
        enabled = true;
        service.Step(t += 0.125);
        AssertEqual(SelfHealthReading.None, service.LastReading, "the switch going off forgets it; nothing is assumed after");
        service.Hold.RememberFullForTest();
        service.Step(t += 0.125);
        AssertEqual<int?>(100, service.LastReading.Percent, "read full again: full");

        service.Step(t += 61);
        service.Dispose();
        AssertEqual(true, lines.Contains("capture=start"), "capture start is written");
        AssertEqual(true, lines.Contains("capture=stop reason=not-readable"), "a stop says why");
        AssertEqual(true, lines.Contains("capture=stop reason=off"), "switching off is written");
        var summary = lines.SingleOrDefault(line => line.StartsWith("summary ", StringComparison.Ordinal))
            ?? throw new InvalidOperationException("one summary line after a minute");
        foreach (var part in new[] { "starts=3", "fullKept=3", "valueRead=0", "avgMs=", "maxMs=", "stop.off=1", "stop.not-readable=1" })
            AssertEqual(true, summary.Contains(part, StringComparison.Ordinal), $"summary has {part}: {summary}");
        AssertEqual(service.SourcesCreated, service.SourcesDisposed, "every created source is disposed");

        // Any health event clears the ring at once, even without a new image (capture failing, only old images), and
        // "full" stays cleared after; a gap with no event keeps it; a death or leaving clears at once too.
        life = Life();
        var again = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, factory, _ => { }) { Life = () => life };
        t = 0;
        again.Step(t += 0.125);
        var current = factory.Made[^1];
        foreach (var gap in new[] { "capture fails", "only old images" })
        {
            void Gap() { if (gap == "capture fails") current.Capture = false; else current.New = false; }
            void Back() { current.Capture = true; current.New = true; }
            again.Hold.RememberFullForTest();
            again.Step(t += 0.125);
            AssertEqual<int?>(100, again.LastReading.Percent, $"{gap}: full");
            Gap();
            again.Step(t += 0.125);
            AssertEqual<int?>(100, again.LastReading.Percent, $"{gap}: a short gap with no health event keeps the ring");
            Back();
            again.Step(t += 0.125);
            AssertEqual<int?>(100, again.LastReading.Percent, $"{gap}: back with no health event: still full");
            Gap();
            life = Life(life.Revision + 1);   // e.g. a death and respawn arrived during the gap
            again.Step(t += 0.125);
            AssertEqual(SelfHealthReading.None, again.LastReading, $"{gap}: a health event clears the ring at once");
            Back();
            again.Step(t += 0.125);
            AssertEqual(SelfHealthReading.None, again.LastReading, $"{gap}: and full stays cleared after");
        }
        again.Hold.RememberFullForTest();
        again.Step(t += 0.125);
        current.New = false;
        life = Life(life.Revision + 1, dead: true);
        again.Step(t += 0.125);
        AssertEqual(SelfHealthReading.None, again.LastReading, "died, no new image: the ring goes at once");
        again.Dispose();
        Console.WriteLine("PASS own health shows full while the tile is folded away and writes counts only");
    }

    // 11-15 user ("满血，只有圆环在闪", 甲): an image with nothing to show keeps the last value shown for up to 0.6 s after it
    // was last really shown, then the ring goes; a black screen, a health event in the log and leaving clear it at once.
    // The minute's summary counts the ring going away, coming back within a second, and the images that kept it.
    static void ServiceKeepsTheRingOverAShortGapOnly()
    {
        var lines = new List<string>();
        var factory = new GrayFactory();
        var life = Life();
        var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, factory, _ => { })
        {
            Life = () => life,
            Diagnostics = new SelfHealthDiagnostics(lines.Add),
        };
        double t = 0;
        service.Step(t += 0.125);
        service.Hold.RememberFullForTest();
        service.Step(t += 0.125);                        // 100 really shown at 0.25
        AssertEqual<int?>(100, service.LastReading.Percent, "full");
        service.Hold.Forget();                           // nothing to show from here on (no tile, no full memory)
        for (int i = 0; i < 4; i++)
        {
            service.Step(t += 0.125);                    // 0.375 .. 0.75: within 0.6 s of the last real value
            AssertEqual<int?>(100, service.LastReading.Percent, $"image {i + 1} with nothing to show, {t - 0.25:0.000} s after: kept");
        }
        service.Step(t += 0.125);                        // 0.875: 0.625 s after
        AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "longer than 0.6 s with nothing to show: the ring goes");
        service.Hold.RememberFullForTest();
        service.Step(t += 0.125);                        // 1.0
        AssertEqual<int?>(100, service.LastReading.Percent, "back");
        service.Step(t += 61);                           // the minute's summary
        var summary = lines.LastOrDefault(line => line.StartsWith("summary ", StringComparison.Ordinal))
            ?? throw new InvalidOperationException("a summary line after a minute");
        var fields = SummaryFields(summary);
        foreach (var (key, want) in new[] { ("ringHidden", "1"), ("ringBackIn1s", "1"), ("shortGapKept", "4"), ("ringDrops", "0"), ("nearFullChanges", "0") })
            AssertEqual(want, fields.GetValueOrDefault(key), $"summary {key}: {summary}");

        // cleared at once: a black screen
        service.Step(t += 0.125);
        AssertEqual<int?>(100, service.LastReading.Percent, "full again");
        factory.Made[^1].Black = true;
        service.Step(t += 0.125);
        AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "a black screen clears the ring at once, no keeping");
        factory.Made[^1].Black = false;
        // a health event in the log (with new images)
        service.Hold.RememberFullForTest();
        service.Step(t += 0.125);
        AssertEqual<int?>(100, service.LastReading.Percent, "full again");
        life = Life(life.Revision + 1);
        service.Step(t += 0.125);
        AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "a health event clears the ring at once, no keeping");
        // leaving
        service.Hold.RememberFullForTest();
        service.Step(t += 0.125);
        AssertEqual<int?>(100, service.LastReading.Percent, "full again");
        life = Life(life.Revision, SelfHealthPresence.Away);
        service.Step(t += 0.125);
        AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "leaving clears the ring at once, no keeping");
        // a value kept over a gap is not kept again from itself: after 0.6 s from the last real value it goes even if
        // the gap is interrupted by nothing else
        life = Life(life.Revision);
        service.Hold.RememberFullForTest();
        service.Step(t += 0.125);
        service.Hold.Forget();
        service.Step(t += 0.5);
        AssertEqual<int?>(100, service.LastReading.Percent, "0.5 s later: kept");
        service.Step(t += 0.125);
        AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "0.625 s after the last real value: gone (kept frames never extend it)");
        service.Dispose();

        // the keep itself (review CX-HUD-RINGFLICKER-073-R1): never a full value over an image under the injured lock
        // (100 shown, then clear low digits while the smoothed value is still full: the hold refuses full with TileUnread
        // and sets the lock); a lower value is kept there; time running backwards keeps nothing
        var gap = new SelfHealthShortGap();
        gap.Next(100, SelfHealthHoldOutcome.Held, false, 0.5);
        AssertEqual(((int?)null, false), gap.Next(null, SelfHealthHoldOutcome.TileUnread, false, 0.625, drop: true), "the hold dropped a value on purpose: nothing kept (review R5 P1)");
        AssertEqual(((int?)null, false), gap.Next(null, SelfHealthHoldOutcome.NoTile, false, 0.75), "and the last value is forgotten");
        gap.Next(100, SelfHealthHoldOutcome.Held, false, 1.0);
        AssertEqual((null, false), gap.Next(null, SelfHealthHoldOutcome.TileUnread, true, 1.125), "injured lock: a kept 100 is not shown");
        AssertEqual((null, false), gap.Next(null, SelfHealthHoldOutcome.TileUnread, false, 1.25), "and it is dropped, not kept for later");
        gap.Next(70, SelfHealthHoldOutcome.Reading, true, 2.0);
        AssertEqual(((int?)70, true), gap.Next(null, SelfHealthHoldOutcome.TileUnread, true, 2.125), "injured lock, last value 70: kept");
        gap.Next(100, SelfHealthHoldOutcome.Held, false, 3.0);
        AssertEqual((null, false), gap.Next(null, SelfHealthHoldOutcome.NoTile, false, 2.9), "time running backwards: nothing kept");
        gap.Next(100, SelfHealthHoldOutcome.Held, false, 4.0);
        AssertEqual((null, false), gap.Next(null, SelfHealthHoldOutcome.Black, false, 4.1), "black: nothing kept");
        gap.Next(100, SelfHealthHoldOutcome.Held, false, 5.0);
        AssertEqual((null, false), gap.Next(null, SelfHealthHoldOutcome.Away, false, 5.1), "away or dead: nothing kept");
        Console.WriteLine("PASS own health keeps the ring over a short gap only and counts the ring going away");
    }

    // "summary k=v k=v ..." into its fields (exact comparison: "hidden=6" must not match "hidden=60")
    static Dictionary<string, string> SummaryFields(string line) => line.Split(' ', StringSplitOptions.RemoveEmptyEntries)
        .Select(part => part.Split('=', 2)).Where(kv => kv.Length == 2).GroupBy(kv => kv[0]).ToDictionary(g => g.Key, g => g.Last()[1]);

    // 11-17 user, through the reader: a join and the first spawn after it start the tile search afresh; the spawn shows
    // full at once where clear digits were read at this capture size before; a health event ends it; never for a life
    // that began before the switch came on or the reader started; counted without values.
    static void ServiceNewLifeFromTheLogIsFull()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-joinfull-" + Guid.NewGuid().ToString("N"));
        try
        {
            var lines = new List<string>();
            var factory = new GrayFactory { Size = (1350, 735) };
            var sizes = new SelfHealthReadableSizes(root);
            bool enabled = true;
            var life = Life(1, SelfHealthPresence.Unknown);
            var service = new SelfHealthReadingService(() => enabled, () => true, () => true, SyntheticModel, factory, _ => { })
            {
                Life = () => life, ReadableSizes = sizes, Diagnostics = new SelfHealthDiagnostics(lines.Add),
            };
            double t = 0;
            service.Step(t += 0.125);
            life = Life(2, SelfHealthPresence.Away, joins: 1);               // joined a server: loading
            service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "loading: no ring");
            life = Life(2, lifeStart: 1, newLife: true, joins: 1);            // the spawn
            service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "this capture size never read clearly: no ring");
            sizes.Add((1350, 735));                                           // as if clear digits had been read here
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "read here before: full after the spawn");
            AssertEqual(SelfHealthState.Normal, service.LastReading.State, "shown as alive");
            for (int i = 0; i < 40; i++) service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "kept while the tile stays folded away");
            life = Life(3, lifeStart: 1, joins: 1);                           // downed
            service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "a health event ends it at once");
            life = Life(3, lifeStart: 2, newLife: true, joins: 1);            // a respawn
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "a respawn: full at once");
            enabled = false;
            service.Step(t += 0.125);
            enabled = true;
            for (int i = 0; i < 20; i++) service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "the switch off and on in that life: no full (not watched begin)");
            factory.Size = (1920, 1046);
            life = Life(4, SelfHealthPresence.Away, joins: 2);
            service.Step(t += 0.125);
            life = Life(4, lifeStart: 3, newLife: true, joins: 2);
            enabled = false; service.Step(t += 0.125); enabled = true;        // a new source at the new size
            life = Life(5, SelfHealthPresence.Away, joins: 3);
            service.Step(t += 0.125);
            life = Life(5, lifeStart: 4, newLife: true, joins: 3);
            for (int i = 0; i < 20; i++) service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "another capture size, never read there: no full");

            // The reader started in the middle of a new life (the Host or the switch came on late): no full.
            factory.Size = (1350, 735);
            life = Life(6, SelfHealthPresence.Away, joins: 4);
            service.Step(t += 0.125);
            life = Life(6, lifeStart: 5, newLife: true, joins: 4);
            var late = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, factory, _ => { })
            {
                Life = () => life, ReadableSizes = sizes,
            };
            for (int i = 0; i < 20; i++) late.Step(i * 0.125);
            AssertEqual(true, late.LastReading.SameValueAs(SelfHealthReading.None), "the reader started in the middle of a new life: no full");
            late.Dispose();

            service.Step(t += 61);
            service.Dispose();
            var summary = lines.First(line => line.StartsWith("summary ", StringComparison.Ordinal));
            var fields = SummaryFields(summary);
            // joins 1, 2 and 4, the first spawns after joins 1 and 3 (join 3 came while the switch was off: taken as seen
            // when reading began again, its spawn still to come; the spawn after join 4 comes after the minute's line),
            // and the new picture size (review R2 P2)
            foreach (var (key, want) in new[] { ("tileSearchRestarts", "6"), ("newLifeWaitingForSize", "21"), ("fullNewLife", "42"), ("valueRead", "0") })
                AssertEqual(want, fields.GetValueOrDefault(key), $"summary {key}={want}: {summary}");
            AssertEqual(false, Directory.Exists(root) && Directory.EnumerateFileSystemEntries(root).Any(p => !p.EndsWith(SelfHealthReadableSizes.FileName, StringComparison.Ordinal)),
                "nothing but the sizes file in the data root");
        }
        finally { try { Directory.Delete(root, true); } catch (DirectoryNotFoundException) { } }
        Console.WriteLine("PASS own health through the reader: a join restarts the tile search, the spawn is full where read before");
    }

    // 11-17 user ("只记读出过和画面尺寸，不存图"): the sizes file holds "WxH" lines only, survives a restart, ignores
    // anything else, and refuses sizes that cannot be a capture.
    static void ReadableSizesKeepSizesOnly()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-readable-" + Guid.NewGuid().ToString("N"));
        try
        {
            var sizes = new SelfHealthReadableSizes(root);
            AssertEqual(false, sizes.Contains((1350, 735)), "nothing read yet");
            sizes.Add((0, 0)); sizes.Add((10, 735)); sizes.Add((1350, 99999));
            AssertEqual(false, File.Exists(Path.Combine(root, SelfHealthReadableSizes.FileName)), "sizes that cannot be a capture are not kept");
            sizes.Add((1350, 735)); sizes.Add((1350, 735)); sizes.Add((900, 490));
            var path = Path.Combine(root, SelfHealthReadableSizes.FileName);
            var written = File.ReadAllLines(path).OrderBy(l => l, StringComparer.Ordinal).ToArray();
            AssertEqual("1350x735|900x490", string.Join('|', written), "one line per size, nothing else");
            AssertEqual(true, sizes.Contains((1350, 735)), "kept");
            AssertEqual(false, sizes.Contains((1350, 736)), "another size is not");
            File.AppendAllText(path, "garbage\n12x12\n-5x40\n 1700x950 \n01800x00950\n1800x900\r\r\n1920x1046\r\n");
            var again = new SelfHealthReadableSizes(root);
            AssertEqual(true, again.Contains((900, 490)) && again.Contains((1920, 1046)), "read back after a restart");
            AssertEqual(false, again.Contains((12, 12)), "too small: ignored");
            AssertEqual(false, again.Contains((1700, 950)) || again.Contains((1800, 950)) || again.Contains((1800, 900)),
                "spaces, leading zeros or a doubled line end: ignored (review R2 P3)");
            File.WriteAllText(path, new string('9', SelfHealthReadableSizes.MaximumFileBytes - 10) + "\n1350x735\n" + new string('9', 20));
            AssertEqual(false, new SelfHealthReadableSizes(root).Contains((1350, 735)), "a file over 4 KB: nothing in it is used");
            AssertEqual(false, Directory.EnumerateFiles(root).Any(p => p.EndsWith(".tmp", StringComparison.Ordinal)), "no temporary file left");
            var memoryOnly = new SelfHealthReadableSizes(null);
            memoryOnly.Add((1350, 735));
            AssertEqual(true, memoryOnly.Contains((1350, 735)), "without a data root: for this run only");
            for (int i = 0; i < SelfHealthReadableSizes.MaximumSizes + 5; i++) sizes.Add((1000 + i, 500));
            AssertEqual(SelfHealthReadableSizes.MaximumSizes, File.ReadAllLines(path).Length, "at most the maximum number of sizes");
        }
        finally { try { Directory.Delete(root, true); } catch (DirectoryNotFoundException) { } }
        Console.WriteLine("PASS own health readable capture sizes keep sizes only");
    }

    // Review CX-HUD-JOINFULL-073-R1: the edges of the join and spawn handling through the reader, and what counts as
    // digits read clearly.
    static void ServiceNewLifeEdges()
    {
        const BindingFlags any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
        void Confirm(HudIconLocator loc)
        {
            typeof(HudIconLocator).GetField("confCx", any)!.SetValue(loc, 339.0);
            typeof(HudIconLocator).GetField("confCy", any)!.SetValue(loc, 250.0);
        }
        var sizes = new SelfHealthReadableSizes(null);
        sizes.Add((1350, 735));
        double t = 0;

        // P2: the switch comes on just after a spawn that happened while it was off (before the next idle poll): no full.
        {
            bool on = false;
            var life = Life(2, SelfHealthPresence.Away, joins: 1);
            var service = new SelfHealthReadingService(() => on, () => true, () => true, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes };
            service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1);
            on = true;
            for (int i = 0; i < 10; i++) service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "a spawn while the switch was off, just before it came on: no full");
            service.Dispose();
        }
        // R2 P2: the switch comes on while the game is behind other windows; the join and spawn come after; then it reads:
        // full (taken as seen when the switch came on, not when reading began).
        {
            bool on = false, front = false;
            var life = Life(1, SelfHealthPresence.Unknown);
            var service = new SelfHealthReadingService(() => on, () => true, () => front, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes };
            service.Step(t += 0.125);
            on = true;
            service.Step(t += 0.125);
            life = Life(2, SelfHealthPresence.Away, joins: 1); service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1); service.Step(t += 0.125);
            front = true;
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "the switch on with the game behind, then a join and spawn, then readable: full");
            service.Dispose();
        }
        // R5 P1: through the reader: the log page stopped (the log not read) ends the new life's 100 at once.
        {
            bool logRead = true;
            var life = Life(1);
            var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes, LogLive = () => logRead };
            service.Step(t += 0.125);
            life = Life(2, SelfHealthPresence.Away, joins: 1); service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1); service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "full after the spawn");
            logRead = false;
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "a moment of no from the log: nothing changes");
            for (int i = 0; i < 24; i++) service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "about 2 s without the log saying in a server: no ring (no short-gap keep)");
            logRead = true;
            for (int i = 0; i < 10; i++) service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "in a server again: the full does not come back (a leave line may have been missed)");
            service.Dispose();
        }
        // R6 P1: the log stops and resumes (or says back at the menu) while the game is behind: the full has ended.
        {
            bool logRead = true, front = true;
            var life = Life(1);
            var service = new SelfHealthReadingService(() => true, () => true, () => front, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes, LogLive = () => logRead };
            service.Step(t += 0.125);
            life = Life(2, SelfHealthPresence.Away, joins: 1); service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1); service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "full after the spawn");
            front = false; service.Step(t += 0.125);
            logRead = false;
            for (int i = 0; i < 6; i++) service.Step(t += 0.5);
            logRead = true;
            front = true;
            for (int i = 0; i < 5; i++) service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "the log said no for 2 s while behind: no full when back");
            service.Dispose();
        }
        // R7 P2: a long wait at the main menu (the log said no for long), then a join and spawn taken in before the next
        // check: full; the log saying in a server keeps it.
        {
            bool logRead = false;
            var life = Life(1);
            var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes, LogLive = () => logRead };
            for (int i = 0; i < 40; i++) service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1);
            logRead = true;
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "after a long main-menu wait, the join and spawn: full");
            for (int i = 0; i < 10; i++) service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "and kept while the log says in a server");
            // a new life begun while the log still says no is ended by the next check
            logRead = false;
            for (int i = 0; i < 24; i++) service.Step(t += 0.125);
            life = Life(3, lifeStart: 2, newLife: true, joins: 1);
            service.Step(t += 0.125);
            for (int i = 0; i < 5; i++) service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "a new life while the log still says no: ended by the next check");
            service.Dispose();
        }
        // R6 P2: the session is published just after the spawn line (a moment of no at the spawn): full still.
        {
            bool logRead = false;
            var life = Life(1);
            var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes, LogLive = () => logRead };
            service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1);
            service.Step(t += 0.125);
            logRead = true;
            for (int i = 0; i < 5; i++) service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "the session published just after the spawn line: full");
            service.Dispose();
        }
        // P2: the reader starts with the game behind other windows; the join and spawn come meanwhile; then it reads: full.
        {
            bool front = false;
            var life = Life(1, SelfHealthPresence.Unknown);
            var service = new SelfHealthReadingService(() => true, () => true, () => front, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes };
            service.Step(t += 0.125);
            life = Life(2, SelfHealthPresence.Away, joins: 1); service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1); service.Step(t += 0.125);
            front = true;
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "a join and spawn while it could not read, then readable: full");
            service.Dispose();
        }
        // P2: a join and spawn taken in together: one restart; a later respawn keeps the confirmed place.
        {
            var lines = new List<string>();
            var life = Life(1);
            var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes, Diagnostics = new SelfHealthDiagnostics(lines.Add) };
            service.Step(t += 0.125);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1);
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "a join and spawn in one batch: full");
            var loc = service.Recognizer!.Loc;
            Confirm(loc);
            life = Life(3, dead: true, lifeStart: 1, joins: 1); service.Step(t += 0.125);
            life = Life(3, lifeStart: 2, newLife: true, joins: 1); service.Step(t += 0.125);
            AssertEqual(true, loc.Confirmed is { cx: 339.0 }, "the respawn after it keeps the confirmed place (no restart left over)");
            service.Step(t += 61);
            service.Dispose();
            var summary = lines.First(line => line.StartsWith("summary ", StringComparison.Ordinal));
            AssertEqual("1", SummaryFields(summary).GetValueOrDefault("tileSearchRestarts"), $"one restart for the batch: {summary}");
        }
        // R2 P2: a respawn on the previous server, leaving and joining another, taken in together while loading: the spawn
        // on the new server is still to come and restarts the tile search.
        {
            var life = Life(1);
            var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes };
            service.Step(t += 0.125);
            life = Life(3, SelfHealthPresence.Away, lifeStart: 1, joins: 1);
            service.Step(t += 0.125);
            var loc = service.Recognizer!.Loc;
            Confirm(loc);
            life = Life(3, lifeStart: 2, newLife: true, joins: 1);
            service.Step(t += 0.125);
            AssertEqual(true, loc.Confirmed is null, "the spawn on the new server restarts the tile search");
            service.Dispose();
        }
        // R3 P2: joined, spawned and downed while switched away: the first image back takes the spawn as done; a later
        // respawn keeps the confirmed place.
        {
            bool front = true;
            var life = Life(1);
            var service = new SelfHealthReadingService(() => true, () => true, () => front, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => life, ReadableSizes = sizes };
            service.Step(t += 0.125);
            front = false; service.Step(t += 0.125);
            life = Life(3, lifeStart: 1, joins: 1);         // joined, spawned, downed
            front = true; service.Step(t += 0.125);
            var loc = service.Recognizer!.Loc;
            Confirm(loc);
            life = Life(4, dead: true, lifeStart: 1, joins: 1); service.Step(t += 0.125);
            life = Life(4, lifeStart: 2, newLife: true, joins: 1); service.Step(t += 0.125);
            AssertEqual(true, loc.Confirmed is { cx: 339.0 }, "a respawn after it keeps the confirmed place");
            service.Dispose();
        }
        // P2: the reader's first image comes while loading after a join: the spawn still restarts the tile search.
        {
            var life = Life(2, SelfHealthPresence.Away, joins: 1);
            var factory = new GrayFactory { Size = (1350, 735) };
            var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, factory, _ => { })
            { Life = () => life, ReadableSizes = sizes };
            service.Step(t += 0.125);
            var loc = service.Recognizer!.Loc;
            Confirm(loc);
            life = Life(2, lifeStart: 1, newLife: true, joins: 1);
            service.Step(t += 0.125);
            AssertEqual(true, loc.Confirmed is null, "the spawn after a join the reader started in: tile search afresh");
            AssertEqual<int?>(100, service.LastReading.Percent, "and full (the spawn was watched)");
            // R4 P1: the picture changes size and the capture rebuilds (no image, no size): the ring goes at once.
            factory.Made[^1].Capture = false;
            service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "the capture rebuilding after a resize: no ring at once");
            factory.Made[^1].Capture = true;
            service.Step(t += 0.125);
            AssertEqual<int?>(100, service.LastReading.Percent, "back at the same size: full again");
            // P2: a new capture size keeps nothing from the old one over a short gap.
            Confirm(loc);
            factory.Made[^1].Size = (1600, 900);
            service.Step(t += 0.125);
            AssertEqual(true, service.LastReading.SameValueAs(SelfHealthReading.None), "another picture size, never read there: nothing kept from the old one");
            AssertEqual(true, loc.Confirmed is null, "and the tile search starts afresh (review R2 P2)");
            service.Dispose();
        }

        // P1: digits read clearly: the network's own digits agree with the value taken for the image, and the units digit
        // is confident. A percent sign with no digit read (all digit slots empty) is not.
        static float[] One(int digit, float p) { var q = Enumerable.Repeat((1 - p) / 10, 11).ToArray(); q[digit] = p; return q; }
        var clear = new HudHealthSample { State = "ok", FrameDigits = 100, CnnRaw = 100, Probs = new float[]?[] { One(0, 0.95f), One(0, 0.9f), One(1, 0.9f) } };
        AssertEqual(true, SelfHealthReadingService.ClearDigitImage(clear), "clear 100");
        AssertEqual(false, SelfHealthReadingService.ClearDigitImage(new HudHealthSample { State = "ok", FrameDigits = 0, CnnRaw = null, Probs = new float[]?[3] }),
            "a percent sign with no digit read: not clear");
        AssertEqual(false, SelfHealthReadingService.ClearDigitImage(new HudHealthSample { State = "ok", FrameDigits = 100, CnnRaw = 10, Probs = clear.Probs }),
            "the network and the filter disagree: not clear");
        AssertEqual(false, SelfHealthReadingService.ClearDigitImage(new HudHealthSample { State = "ok", FrameDigits = 100, CnnRaw = 100,
            Probs = new float[]?[] { One(0, 0.5f), One(0, 0.9f), One(1, 0.9f) } }), "an unsure units digit: not clear");
        AssertEqual(false, SelfHealthReadingService.ClearDigitImage(new HudHealthSample { State = "black", FrameDigits = 100, CnnRaw = 100, Probs = clear.Probs }),
            "a black image: not clear");
        AssertEqual(false, SelfHealthReadingService.ClearDigitImage(new HudHealthSample { State = "ok", FrameDigits = 7, CnnRaw = 7,
            Probs = new float[]?[] { One(7, 0.95f), null, null } }), "only the units place cut from the image (review R2 P1): not clear");
        AssertEqual(false, SelfHealthReadingService.ClearDigitImage(new HudHealthSample { State = "ok", FrameDigits = 0, CnnRaw = 0,
            Probs = new float[]?[] { One(0, 0.95f), One(10, 0.95f), One(10, 0.95f) } }), "zero: not a clear reading of a living player");
        var seventy = new HudHealthSample { State = "ok", FrameDigits = 70, CnnRaw = 70, Probs = new float[]?[] { One(0, 0.95f), One(7, 0.9f), One(10, 0.9f) } };
        AssertEqual(true, SelfHealthReadingService.ClearDigitImage(seventy), "70 with a clear blank hundreds place: clear");
        AssertEqual(false, SelfHealthReadingService.ClearDigitImage(new HudHealthSample { State = "ok", FrameDigits = 70, CnnRaw = 70,
            Probs = new float[]?[] { One(0, 0.95f), One(7, 0.9f), One(10, 0.5f) } }), "an unsure blank place: not clear");

        // Through the reader's own record (review R2 P3): two clear images in a row at one size record it; anything else
        // in between, a new size, or capture stopping starts the count again.
        {
            bool enabled = true;
            var mine = new SelfHealthReadableSizes(null);
            var service = new SelfHealthReadingService(() => enabled, () => true, () => true, SyntheticModel, new GrayFactory(), _ => { })
            { Life = () => Life(1), ReadableSizes = mine };
            var unclear = new HudHealthSample { State = "ok", FrameDigits = 70, CnnRaw = null, Probs = new float[]?[3] };
            var a = (1350, 735); var b = (1600, 900);
            service.NoteSize(a);
            service.NoteDigits(clear, a); service.NoteDigits(unclear, a); service.NoteDigits(clear, a);
            AssertEqual(false, mine.Contains(a), "clear, unclear, clear: not recorded");
            service.NoteDigits(seventy, a);
            AssertEqual(true, mine.Contains(a), "two clear in a row: recorded");
            service.NoteSize(b);
            service.NoteDigits(clear, b);
            service.NoteSize(a); service.NoteSize(b);
            service.NoteDigits(clear, b);
            AssertEqual(false, mine.Contains(b), "a size change in between starts the count again");
            service.NoteDigits(clear, b);
            AssertEqual(true, mine.Contains(b), "then two in a row at that size: recorded");
            var c = (1700, 950);
            service.NoteSize(c);
            service.Step(t += 0.125);
            service.NoteDigits(clear, c);
            enabled = false; service.Step(t += 0.125); enabled = true;
            service.NoteDigits(clear, c);
            AssertEqual(false, mine.Contains(c), "capture stopping in between starts the count again");
            service.Dispose();
        }
        // Review R3 P3: the reader's own step goes through the record (a grey image is not clear and breaks the run).
        {
            var mine = new SelfHealthReadableSizes(null);
            var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, new GrayFactory { Size = (1350, 735) }, _ => { })
            { Life = () => Life(1), ReadableSizes = mine };
            service.Step(t += 0.125);
            service.NoteDigits(clear, (1350, 735));
            service.Step(t += 0.125);
            service.NoteDigits(clear, (1350, 735));
            AssertEqual(false, mine.Contains((1350, 735)), "an image the reader read in between (not clear) breaks the run");
            service.Dispose();
        }
        Console.WriteLine("PASS own health join and spawn edges through the reader (switch timing, one batch, size change, clear digits)");
    }

    static void MissingModelNeverStartsCapture()
    {
        var factory = new FakeFactory();
        using var service = new SelfHealthReadingService(() => true, () => true, () => true, () => null, factory, _ => { });
        for (int i = 0; i < 5; i++) service.Step(i * 0.125);
        AssertEqual(0, factory.Made.Count, "without the private model nothing is captured");
        AssertEqual(false, service.ModelAvailable, "model reported unavailable");
        Console.WriteLine("PASS own health stays off without the private model");
    }

    sealed class ThrowingSource : IHudFrameSource
    {
        public int Disposed;
        public bool TryCapture(HudPanelFrame frame) => throw new InvalidOperationException("desktop duplication failed");
        public void Dispose() => Interlocked.Increment(ref Disposed);
    }

    sealed class ThrowingFactory : IHudFrameSourceFactory
    {
        public readonly List<ThrowingSource> Made = new();
        public IHudFrameSource? TryCreate() { var s = new ThrowingSource(); lock (Made) Made.Add(s); return s; }
    }

    // A failed capture (lost access, device removed, anything but "no new frame") releases the source,
    // clears the reading and recreates later; no stale copy keeps being read.
    static void CaptureErrorsReleaseTheSourceAndRetry()
    {
        var factory = new ThrowingFactory();
        var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, factory, _ => { },
            readsPerSecond: 30) { IdlePoll = TimeSpan.FromMilliseconds(20), RetryAfterFailure = TimeSpan.FromMilliseconds(50) };
        service.Start();
        var waited = System.Diagnostics.Stopwatch.StartNew();
        while (waited.Elapsed < TimeSpan.FromSeconds(5)) { lock (factory.Made) if (factory.Made.Count >= 3) break; Thread.Sleep(20); }
        service.Dispose();
        lock (factory.Made)
        {
            if (factory.Made.Count < 3) throw new InvalidOperationException("failed sources are recreated after the retry wait");
            AssertEqual(true, factory.Made.All(m => m.Disposed == 1), "every failed source is released exactly once");
        }
        AssertEqual(SelfHealthReading.None, service.LastReading, "a failed capture leaves no reading");
        Console.WriteLine("PASS own health capture errors release the source, clear the reading and retry");
    }

    sealed class BlockingSource : IHudFrameSource
    {
        public readonly ManualResetEventSlim Entered = new(), Release = new();
        public int Disposed, Captures;
        // The first FreeCaptures calls return at once (so a valid reading can go out first); then it blocks.
        public int FreeCaptures;
        public bool TryCapture(HudPanelFrame frame)
        {
            if (Interlocked.Increment(ref Captures) <= FreeCaptures) return true;
            Entered.Set(); Release.Wait(); return true;
        }
        public void Dispose() => Interlocked.Increment(ref Disposed);
    }

    sealed class BlockingFactory : IHudFrameSourceFactory
    {
        public readonly BlockingSource Source = new();
        public int Made;
        public IHudFrameSource? TryCreate() => Interlocked.Increment(ref Made) == 1 ? Source : null;
    }

    // A driver call that blocks longer than Dispose waits: Dispose returns, but the capture objects stay with
    // the reader thread and are released by it, once, when the call returns; nothing is captured afterwards.
    static void BlockedCaptureIsReleasedOnlyByTheReader()
    {
        var factory = new BlockingFactory();
        factory.Source.FreeCaptures = 2;
        var published = new List<SelfHealthReading>();
        // The game log says "dead", so the first captures publish a valid reading (0%, dead) before the block:
        // the "nothing valid after Dispose" check below then has something to rule out.
        var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, factory,
            r => { lock (published) published.Add(r); }, lifeState: () => SelfHealthState.Dead, readsPerSecond: 30) { IdlePoll = TimeSpan.FromMilliseconds(20) };
        try
        {
            service.Start();
            if (!factory.Source.Entered.Wait(TimeSpan.FromSeconds(5))) throw new InvalidOperationException("capture started");
            lock (published) AssertEqual(true, published.Any(r => r.State == SelfHealthState.Dead), "a valid reading went out before the blocked call");
            var stop = System.Diagnostics.Stopwatch.StartNew();
            service.Dispose();
            if (stop.Elapsed > TimeSpan.FromSeconds(5)) throw new InvalidOperationException("dispose is bounded");
            int publishedAtDispose; lock (published) publishedAtDispose = published.Count;
            AssertEqual(0, factory.Source.Disposed, "a source still in use by the reader is not released from another thread");
            AssertEqual(false, service.Stopped, "the reader is still inside the blocked call");
            AssertEqual(false, service.CancellationReleased, "the cancellation source is left to the reader");
            factory.Source.Release.Set();
            var waited = System.Diagnostics.Stopwatch.StartNew();
            while (!service.Stopped && waited.Elapsed < TimeSpan.FromSeconds(5)) Thread.Sleep(20);
            AssertEqual(true, service.Stopped, "the reader finishes after the call returns");
            AssertEqual(1, factory.Source.Disposed, "the reader releases the source exactly once");
            AssertEqual(true, service.CancellationReleased, "the reader frees the cancellation source when it finishes");
            lock (published)
                AssertEqual(true, published.Skip(publishedAtDispose).All(r => r == SelfHealthReading.None),
                    "after Dispose nothing but \"no reading\" is published");
            AssertEqual(SelfHealthReading.None, service.LastReading, "the last word after stopping is \"no reading\"");
            var captures = factory.Source.Captures;
            Thread.Sleep(200);
            AssertEqual(captures, factory.Source.Captures, "nothing is captured after stopping");
            AssertEqual(1, factory.Made, "no new source is created after stopping");
            service.Dispose();
            Console.WriteLine("PASS own health blocked capture is released only by the reader, once, after Dispose");
        }
        finally
        {
            // Never leave the reader blocked if an assertion above failed: stop it first, then unblock it.
            service.Dispose();
            factory.Source.Release.Set();
            var waited = System.Diagnostics.Stopwatch.StartNew();
            while (!service.Stopped && waited.Elapsed < TimeSpan.FromSeconds(5)) Thread.Sleep(20);
        }
    }

    // R3/R4 review: the gap between "not stopped yet" and the publish itself. A publish that has passed the
    // check and is going out holds the publish lock: Dispose waits for it, and after the stop nothing valid
    // goes out, only the final "no reading". Each reading differs from the last, so de-duplication cannot hide a leak.
    static void DisposeWaitsForAPublishInFlightAndNothingValidFollows()
    {
        var published = new List<SelfHealthReading>();
        var inside = new ManualResetEventSlim(); var release = new ManualResetEventSlim(); var disposeEntered = new ManualResetEventSlim();
        int lifeCalls = 0, valid = 0;
        SelfHealthState Life() => Interlocked.Increment(ref lifeCalls) % 2 == 0 ? SelfHealthState.Dead : SelfHealthState.Downed;
        var service = new SelfHealthReadingService(() => true, () => true, () => true, SyntheticModel, new FakeFactory(),
            r =>
            {
                lock (published) published.Add(r);
                if (r != SelfHealthReading.None && Interlocked.Increment(ref valid) == 3) { inside.Set(); release.Wait(TimeSpan.FromSeconds(10)); }
            }, lifeState: Life, readsPerSecond: 30) { IdlePoll = TimeSpan.FromMilliseconds(20), OnDisposeEntering = () => disposeEntered.Set() };
        Task? disposing = null;
        try
        {
            service.Start();
            if (!inside.Wait(TimeSpan.FromSeconds(5))) throw new InvalidOperationException("a third valid reading is going out");
            disposing = Task.Run(service.Dispose);
            // Dispose has really started (it is at the publish lock) before anything is asserted.
            if (!disposeEntered.Wait(TimeSpan.FromSeconds(5))) throw new InvalidOperationException("Dispose started");
            Thread.Sleep(200);
            AssertEqual(false, disposing.IsCompleted, "Dispose waits for the publish already going out");
            AssertEqual(false, service.StopRequested, "the stop is not requested while a publish that passed the check is going out");
            int atRelease; lock (published) atRelease = published.Count;
            release.Set();
            if (!disposing.Wait(TimeSpan.FromSeconds(5))) throw new InvalidOperationException("Dispose finishes once the publish is out");
            var waited = System.Diagnostics.Stopwatch.StartNew();
            while (!service.Stopped && waited.Elapsed < TimeSpan.FromSeconds(5)) Thread.Sleep(20);
            Thread.Sleep(200);
            lock (published)
            {
                var after = published.Skip(atRelease).ToList();
                AssertEqual(true, after.All(r => r == SelfHealthReading.None), "after the stop nothing valid is published");
                AssertEqual(true, after.Count >= 1, "the final \"no reading\" is actually published");
            }
            Console.WriteLine("PASS own health Dispose waits for a publish in flight and nothing valid follows");
        }
        finally
        {
            release.Set();
            service.Dispose();
            disposing?.Wait(TimeSpan.FromSeconds(5));
        }
    }

    // R4/R5 review: when the service stops capturing, the learned digit scale and its whole history are dropped,
    // so a new start (maybe with another HUD scale) learns it again. Goes through the service's own stop path.
    static void StopResetsTheDigitScale()
    {
        bool enabled = true;
        var service = new SelfHealthReadingService(() => enabled, () => true, () => true, SyntheticModel, new FakeFactory(), _ => { });
        for (int i = 0; i < 3; i++) service.Step(i * 0.125);
        var reader = service.Recognizer?.Digits ?? throw new InvalidOperationException("recognizer created while capturing");
        const System.Reflection.BindingFlags any = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public;
        var t = typeof(HudDigitReader);
        // A learned history: scale 0.92 after 40 sweeps with averages favouring it.
        t.GetProperty("LastScale", any)!.GetSetMethod(true)!.Invoke(reader, new object[] { 0.92 });
        t.GetField("avgCount", any)!.SetValue(reader, 40);
        t.GetField("frameNo", any)!.SetValue(reader, 400L);
        var avg = (double[])t.GetField("pctAvg", any)!.GetValue(reader)!;
        for (int i = 0; i < avg.Length; i++) avg[i] = 0.5 + 0.01 * i;
        enabled = false;
        service.Step(1.0);   // the switch goes off: capture stops
        AssertEqual(1.0, reader.LastScale, "the learned scale is dropped when capture stops");
        AssertEqual(0, (int)t.GetField("avgCount", any)!.GetValue(reader)!, "the averaging starts again");
        AssertEqual(0L, (long)t.GetField("frameNo", any)!.GetValue(reader)!, "the sweep schedule starts again");
        AssertEqual(true, avg.All(x => x == 0), "the per-scale averages are cleared");
        service.Dispose();
        Console.WriteLine("PASS own health stopping capture resets the learned digit scale and its history");
    }

    // R5 review: a bright background marks the ring as untrusted even when the ring itself could not be read.
    static void BrightBackgroundMarksTheRingEvenWhenItWasNotRead()
    {
        var frame = new HudPanelFrame();
        Array.Fill(frame.Bgr, (byte)220);
        var s = new HudHealthSample { State = "ok", ArcDeg = -1 };
        HudHealthRecognizer.ApplyBrightBackground(s, frame, 300, 250, 30, 150);
        AssertEqual(true, s.RingUnreliable, "bright floor: ring untrusted even though it was not read");
        var dark = new HudPanelFrame();
        var d = new HudHealthSample { State = "ok", ArcDeg = 200, RingEst = 52 };
        HudHealthRecognizer.ApplyBrightBackground(d, dark, 300, 250, 30, 150);
        AssertEqual(false, d.RingUnreliable, "dark scene: ring kept");
        AssertEqual(200, d.ArcDeg, "dark scene: ring reading kept");
        Console.WriteLine("PASS own health a bright background marks the ring untrusted whether or not it was read");
    }

    // Dispose that finds the reader already finished frees the cancellation source itself, once.
    static void PromptDisposeFreesTheCancellationSource()
    {
        var service = new SelfHealthReadingService(() => false, () => true, () => true, SyntheticModel, new FakeFactory(), _ => { })
            { IdlePoll = TimeSpan.FromMilliseconds(20) };
        service.Start();
        Thread.Sleep(60);
        service.Dispose();
        AssertEqual(true, service.Stopped, "reader finished");
        AssertEqual(true, service.CancellationReleased, "cancellation source freed by Dispose");
        service.Dispose();
        Console.WriteLine("PASS own health prompt Dispose frees the cancellation source once");
    }

    static void ThrowingLoaderNeverStartsCapture()
    {
        var factory = new FakeFactory();
        using var service = new SelfHealthReadingService(() => true, () => true, () => true,
            () => throw new InvalidDataException("bad model"), factory, _ => { });
        for (int i = 0; i < 3; i++) service.Step(i * 0.125);
        AssertEqual(0, factory.Made.Count, "a model that fails to load never starts capture");
    }

    // ---- model file ----------------------------------------------------------------------

    static readonly (string Name, int[] Shape)[] CnnShapes =
    {
        ("f.0.weight", new[] { 16, 1, 3, 3 }), ("f.0.bias", new[] { 16 }),
        ("f.3.weight", new[] { 32, 16, 3, 3 }), ("f.3.bias", new[] { 32 }),
        ("f.6.weight", new[] { 48, 32, 3, 3 }), ("f.6.bias", new[] { 48 }),
        ("f.10.weight", new[] { 64, 144 }), ("f.10.bias", new[] { 64 }),
        ("f.13.weight", new[] { 11, 64 }), ("f.13.bias", new[] { 11 }),
    };

    // A model with the right shapes and synthetic values (a drawn plus sign, a drawn box, zero weights).
    static HudHealthModel SyntheticModel() => HudHealthModel.Load(new MemoryStream(SyntheticModelBytes()));

    static byte[] SyntheticModelBytes(params (string, int[], float[])[] extra)
    {
        var blocks = new List<(string, int[], float[])> { ("plus.scales", new[] { 3 }, new[] { 0.92f, 1f, 1.08f }) };
        int[] sizes = { 31, 34, 37 };
        for (int i = 0; i < 3; i++)
        {
            int n = sizes[i]; var d = new float[n * n];
            for (int k = n / 4; k < n * 3 / 4; k++) { d[(n / 2) * n + k] = 255; d[k * n + n / 2] = 255; }
            blocks.Add(($"plus.{i}", new[] { n, n }, d));
        }
        var pct = new float[25 * 17];
        for (int y = 2; y < 23; y++) for (int x = 2; x < 15; x++) pct[y * 17 + x] = (x + y) % 5 == 0 ? 220 : 30;
        blocks.Add(("pct.0", new[] { 25, 17 }, pct));
        foreach (var (name, shape) in CnnShapes) blocks.Add(("cnn." + name, shape, new float[shape.Aggregate(1, (a, b) => a * b)]));
        blocks.Add(("const.r0_thr", new[] { 2 }, new[] { 30f, 0.45f }));
        blocks.AddRange(extra);
        var ms = new MemoryStream(); using var w = new BinaryWriter(ms);
        w.Write(Encoding.ASCII.GetBytes("SBHH")); w.Write(1); w.Write(blocks.Count);
        foreach (var (name, shape, data) in blocks)
        {
            var nb = Encoding.UTF8.GetBytes(name); w.Write(nb.Length); w.Write(nb);
            w.Write(shape.Length); foreach (var s in shape) w.Write(s);
            foreach (var v in data) w.Write(v);
        }
        w.Flush(); return ms.ToArray();
    }

    static void ModelFileRoundTripsAndRejectsDamage()
    {
        var m = SyntheticModel();
        AssertEqual(3, m.Plus.Count, "three plus sizes");
        AssertEqual(34, m.Plus[1].W, "middle plus size");
        AssertEqual(1, m.Pct.Count, "percent templates");
        AssertEqual(10, m.Cnn.Count, "all CNN tensors");
        var bytes = SyntheticModelBytes();
        var badMagic = (byte[])bytes.Clone(); badMagic[0] = (byte)'X';
        ExpectInvalid(badMagic, "wrong magic is rejected");
        ExpectInvalid(bytes.AsSpan(0, bytes.Length / 2).ToArray(), "truncated file is rejected");
        var badVersion = (byte[])bytes.Clone(); badVersion[4] = 9;
        ExpectInvalid(badVersion, "unknown version is rejected");
        Console.WriteLine("PASS own health model file round-trips and rejects damaged files");
    }

    static void ExpectInvalid(byte[] data, string label)
    {
        try { HudHealthModel.Load(new MemoryStream(data)); }
        catch (Exception e) when (e is InvalidDataException or EndOfStreamException) { return; }
        throw new InvalidOperationException(label);
    }

    // The synthetic model with one tensor replaced by the given shape, every value set to fill.
    static byte[] SyntheticModelBytesWith(string block, int[] shape, float fill)
    {
        var ok = SyntheticModelBytes();
        var m = new MemoryStream(); using var w = new BinaryWriter(m);
        using var r = new BinaryReader(new MemoryStream(ok));
        w.Write(r.ReadBytes(4)); w.Write(r.ReadInt32()); int count = r.ReadInt32(); w.Write(count);
        for (int b = 0; b < count; b++)
        {
            int nl = r.ReadInt32(); var nb = r.ReadBytes(nl); var name = Encoding.UTF8.GetString(nb);
            int rank = r.ReadInt32(); var sh = new int[rank]; for (int i = 0; i < rank; i++) sh[i] = r.ReadInt32();
            int n = sh.Aggregate(1, (x, c) => x * c); var data = r.ReadBytes(n * 4);
            w.Write(nl); w.Write(nb);
            if (name == block)
            {
                w.Write(shape.Length); foreach (var x in shape) w.Write(x);
                int n2 = shape.Aggregate(1, (x, c) => x * c); for (int i = 0; i < n2; i++) w.Write(fill);
            }
            else { w.Write(rank); foreach (var x in sh) w.Write(x); w.Write(data); }
        }
        w.Flush(); return m.ToArray();
    }

    static void ModelWithWrongNetworkShapeIsRejected()
    {
        ExpectInvalid(SyntheticModelBytesWith("cnn.f.0.weight", new[] { 1, 1, 3, 3 }, 0f), "one-channel first layer is rejected");
        ExpectInvalid(SyntheticModelBytesWith("cnn.f.10.weight", new[] { 64, 96 }, 0f), "wrong fully connected size is rejected");
        ExpectInvalid(SyntheticModelBytesWith("cnn.f.13.bias", new[] { 11 }, float.NaN), "NaN weights are rejected");
        ExpectInvalid(SyntheticModelBytesWith("cnn.f.3.bias", new[] { 32 }, float.PositiveInfinity), "infinite weights are rejected");
        ThrowingLoaderNeverStartsCapture();
        Console.WriteLine("PASS own health model with a wrong network shape or non-finite values is rejected before capture");
    }

    // ---- scaling -------------------------------------------------------------------------

    static void PanelScalerKeepsLayout()
    {
        var frame = new HudPanelFrame();
        var same = new byte[HudPanelFrame.W * HudPanelFrame.H * 4];
        same[0] = 10; same[1] = 20; same[2] = 30; same[3] = 255;
        HudPanelScaler.FromBgra(same, HudPanelFrame.W, HudPanelFrame.H, frame);
        AssertEqual((byte)30, frame.Bgr[2], "2560x1440 region is copied as is (BGR)");
        int rw = 675, rh = 368; var small = new byte[rw * rh * 4];
        for (int i = 0; i < small.Length; i += 4) { small[i] = 200; small[i + 1] = 100; small[i + 2] = 50; }
        HudPanelScaler.FromBgra(small, rw, rh, frame);
        int last = (HudPanelFrame.W * HudPanelFrame.H - 1) * 3;
        AssertEqual((byte)200, frame.Bgr[last], "1080p region fills the whole panel");
        AssertEqual((byte)50, frame.Bgr[last + 2], "channel order kept when scaling");
        // A horizontal ramp keeps its position: left edge dark, right edge bright, middle about half.
        for (int y = 0; y < rh; y++) for (int x = 0; x < rw; x++) { int i = (y * rw + x) * 4; small[i] = small[i + 1] = small[i + 2] = (byte)(x * 255 / (rw - 1)); }
        HudPanelScaler.FromBgra(small, rw, rh, frame);
        int row = 245 * HudPanelFrame.W * 3;
        int left = frame.Bgr[row], mid = frame.Bgr[row + 450 * 3], right = frame.Bgr[row + 899 * 3];
        if (left > 2 || right < 253 || Math.Abs(mid - 128) > 3) throw new InvalidOperationException($"ramp misplaced: {left}/{mid}/{right}");
        for (int x = 1; x < HudPanelFrame.W; x++)
            if (frame.Bgr[row + x * 3] < frame.Bgr[row + (x - 1) * 3]) throw new InvalidOperationException("ramp is not monotonic");
        Console.WriteLine("PASS own health panel scaler keeps the 2560x1440 layout");
    }

    // ---- privacy -------------------------------------------------------------------------

    // The reading is for the visor's own row on this machine only: no type outside the health
    // reading itself may hold it, and nothing in relay, presence, sharing or realtime code may
    // carry a health member.
    static void HealthNeverReachesSharedOrRelayTypes()
    {
        var healthTypes = new HashSet<Type> { typeof(SelfHealthReading), typeof(SelfHealthReadingHub), typeof(SelfHealthState), typeof(SelfHealthReading[]) };
        var assemblies = new[] { typeof(SelfHealthReading).Assembly, typeof(StarBridge.Core.Presence.PlayerPresence).Assembly };
        var offenders = new List<string>();
        const BindingFlags all = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly;
        foreach (var asm in assemblies)
            foreach (var type in SafeTypes(asm))
            {
                var ns = type.Namespace ?? "";
                if (ns == typeof(SelfHealthReading).Namespace) continue;
                foreach (var f in type.GetFields(all)) if (healthTypes.Contains(f.FieldType)) offenders.Add($"{type.FullName}.{f.Name}");
                foreach (var p in type.GetProperties(all)) if (healthTypes.Contains(p.PropertyType)) offenders.Add($"{type.FullName}.{p.Name}");
                bool shared = ns.Contains("Relay", StringComparison.OrdinalIgnoreCase) || ns.Contains("Presence", StringComparison.OrdinalIgnoreCase)
                    || ns.Contains("Realtime", StringComparison.OrdinalIgnoreCase) || ns.Contains("Sharing", StringComparison.OrdinalIgnoreCase)
                    || type.Name.Contains("Relay", StringComparison.OrdinalIgnoreCase) || type.Name.Contains("Shared", StringComparison.OrdinalIgnoreCase);
                if (!shared) continue;
                foreach (var m in type.GetMembers(all))
                    if (HealthName.IsMatch(m.Name) && m.MemberType is MemberTypes.Field or MemberTypes.Property)
                        offenders.Add($"{type.FullName}.{m.Name}");
            }
        if (offenders.Count > 0) throw new InvalidOperationException("health reaches shared or relay types: " + string.Join(", ", offenders));
        Console.WriteLine("PASS own health never reaches shared, presence or relay types");
    }

    // Health of a player, not "healthy" connections or health checks.
    static readonly System.Text.RegularExpressions.Regex HealthName = new(
        "(?i)(selfhealth|ownhealth|playerhealth|healthpercent|healthstate|healthreading|healthvalue|hitpoint)");

    static IEnumerable<Type> SafeTypes(Assembly a)
    {
        try { return a.GetTypes(); }
        catch (ReflectionTypeLoadException e) { return e.Types.Where(t => t != null)!; }
    }

    // ---- visor mapping -------------------------------------------------------------------

    static void VisorMappingFollowsTheRingRules()
    {
        var now = DateTimeOffset.UnixEpoch;
        AssertEqual((SelfHealthVisorKind.Unknown, 0f), SelfHealthReading.None.ToVisor(), "no reading: no ring drawn");
        AssertEqual((SelfHealthVisorKind.Alive, 0.78f), new SelfHealthReading(78, SelfHealthState.Normal, now).ToVisor(), "78% alive");
        AssertEqual((SelfHealthVisorKind.Alive, 1f), new SelfHealthReading(100, SelfHealthState.Normal, now).ToVisor(), "full");
        AssertEqual((SelfHealthVisorKind.Downed, 0.05f), new SelfHealthReading(5, SelfHealthState.Downed, now).ToVisor(), "downed");
        AssertEqual((SelfHealthVisorKind.Dead, 0f), new SelfHealthReading(0, SelfHealthState.Dead, now).ToVisor(), "dead");
        AssertEqual((int)SelfHealthVisorKind.Dead, 3, "order matches the visor enum");
        Console.WriteLine("PASS own health maps to the visor ring (alive 0..1, downed, dead, unknown)");
    }

    // ---- private model -------------------------------------------------------------------

    // Same input as the training check in the lab (a synthetic ramp); the hand-written CNN must
    // agree with PyTorch. Skipped where the private model is not staged.
    static void PrivateModelMatchesTrainingOutput()
    {
        var path = Path.Combine(HostTestSource.Root, ".private-ops", "hud-health", HudHealthModel.FileName);
        if (!File.Exists(path))
        {
            new RestrictedSampleAbsentException(HudHealthModel.FileName, "model").Report("own health private model check");
            return;
        }
        var model = HudHealthModel.Load(path);
        AssertEqual(3, model.Alt.Count, "the private model carries the suffocation icon in three sizes");
        var cnn = new HudDigitCnn(model);
        var patch = Enumerable.Range(0, 275).Select(i => (float)((i * 37) % 256)).ToArray();
        var p = cnn.Predict(patch);
        AssertEqual(10, Array.IndexOf(p, p.Max()), "ramp reads as an empty slot");
        if (Math.Abs(p[10] - 0.8620f) > 0.002f || Math.Abs(p[7] - 0.0266f) > 0.001f)
            throw new InvalidOperationException($"CNN differs from training output: p10={p[10]}, p7={p[7]}");
        Console.WriteLine("PASS own health CNN matches the training output");
    }

    static void AssertEqual<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"{label}: expected '{expected}', actual '{actual}'.");
    }
}

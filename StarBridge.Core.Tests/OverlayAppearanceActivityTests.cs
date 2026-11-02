using StarBridge.Desktop;
namespace StarBridge.Core.Tests;
internal static class OverlayAppearanceActivityTests
{
    internal static void RunAll()
    {
        static void Check(bool ok,string message){if(!ok)throw new InvalidOperationException(message);}
        Check(OverlayAppearanceSamplingDeadline.IntervalTicks(120,0,120000)==1000,"Native cadence must remain the default");
        Check(OverlayAppearanceSamplingDeadline.IntervalTicks(120,200,120000)==24000,"Quiet deadline must reduce sampling, not animation time");
        Check(OverlayAppearanceSamplingDeadline.IntervalTicks(120,1,120000)==120,"Near held-cel boundary must wake without missing the next cel");
        Check(OverlayAppearanceSamplingDeadline.IntervalTicks(120,9999,120000)==24000,"Optional deadline must stay below the controller clock bound");
        Check(OverlayAppearanceSamplingDeadline.IntervalTicks(999,-1,120000)==500,"Invalid optional delay must preserve bounded native FPS");
        Check(OverlayAppearanceSamplingDeadline.IntervalTicks(0,0,0)==1,"Invalid frequency must not yield an immediate spin");
        var now=new DateTimeOffset(2026,10,7,12,0,0,TimeSpan.Zero);
        var cursor=new OverlayAppearanceActivityCursor();
        Check(cursor.Observe([new(1,now)],1,true,now,0).Count==0,"Initial snapshot must be history");
        var batch=cursor.Observe([new(3,now),new(2,now),new(2,now)],1,true,now,100);
        Check(batch.Select(s=>s.Sequence).SequenceEqual(new long[]{2,3}),"Sort and deduplicate simultaneous activities");
        for(var i=0;i<10000;i++)Check(cursor.Observe([new(3,now)],1,true,now,100+i).Count==0,"Animation/pulse must not repeat activity");
        Check(cursor.Observe([new(4,now.AddSeconds(-6))],1,true,now,11000).Count==0,"Stale queued event must not react");
        Check(cursor.Observe([new(5,now.AddSeconds(1))],1,true,now,12000).Count==0,"Future clock evidence must not react");
        Check(cursor.Observe([new(6,now)],1,false,now,13000).Count==0,"Hidden/static snapshot must be consumed");
        Check(cursor.Observe([new(6,now)],1,true,now,14000).Count==0,"Ineligible event must not replay");
        cursor.Rebase();
        Check(cursor.Observe([new(7,now)],1,true,now,15000).Count==0,"Reopening history must baseline");
        Check(cursor.Observe([new(8,now)],1,true,now,16000).Single().Sequence==8,"Fresh event after show must arrive");
        Check(cursor.Observe([new(9,now)],2,true,now,17000).Count==0,"Source epoch change must baseline");
        Check(cursor.Observe([new(99,now)],1,true,now,18000).Count==0,"Delayed former-source snapshot must not consume new source IDs");
        Check(cursor.Observe([new(10,now.AddMilliseconds(1875))],2,true,now.AddSeconds(2),19000).Single().OccurredAtMs==18875,"Preserve event age in monotonic time");
        cursor.Rebase();cursor.Observe([],2,true,now.AddSeconds(3),20000);
        Check(cursor.Observe([new(11,now.AddMilliseconds(2900))],2,true,now.AddMilliseconds(3100),20100).Count==0,"Pending event born before reopening must not react even if it is under five seconds old");
        Check(cursor.Observe([new(12,now.AddMilliseconds(3150))],2,true,now.AddMilliseconds(3200),20200).Single().Sequence==12,"Newly born event after reopening must still arrive");
        var stamps=Enumerable.Range(0,1000).AsParallel().Select(_=>OverlayAppearanceActivity.Create(now)).ToArray();
        Check(stamps.Select(s=>s.Sequence).Distinct().Count()==1000,"Concurrent activity IDs must be unique");
        Check(typeof(OverlayAppearanceActivity).GetProperties().Select(p=>p.Name).Order().SequenceEqual(new[]{"OccurredAt","Sequence"}),"Activity stamp must not expose event text or identities");
        var combined = new OverlayAppearanceActivityCursor();
        combined.Observe([], 1, true, now, 0);
        var notice = OverlayAppearanceActivity.Create(now.AddMilliseconds(10));
        var chat = OverlayAppearanceActivity.Create(now.AddMilliseconds(20));
        var game = OverlayAppearanceActivity.Create(now.AddMilliseconds(30));
        Check(combined.Observe([game, chat, notice, chat], 1, true, now.AddMilliseconds(40), 40)
            .Select(signal => signal.Sequence).SequenceEqual(new[] { notice.Sequence, chat.Sequence, game.Sequence }),
            "Combined communication/game activity shares one ordered deduplicated stream");
        Check(combined.Observe([notice,chat,game],1,true,now.AddSeconds(1),1000).Count==0,
            "Persistent notice and rebuilt chat snapshots cannot repeat reactions");
        var queued = OverlayAppearanceActivity.Create(now.AddMilliseconds(50));
        Check(combined.Observe([queued],1,true,now.AddSeconds(6),6000).Count==0,
            "Delayed announcement/chat promotion preserves age and does not replay");
        var invalidator = new OverlayAppearanceFrameInvalidator();
        Check(invalidator.Observe(1,0), "Initial installed frame must paint");
        for (var i=0;i<10000;i++) Check(!invalidator.Observe(1,0), "Unchanged held cel must not dirty the surface");
        Check(invalidator.Observe(1,1), "New held cel must paint at the original clock tick");
        Check(invalidator.Observe(2,1), "Replacement owner must paint even with an equal visual version");
        Check(!invalidator.Observe(2,1), "Replacement's unchanged cel must settle");
        Check(invalidator.Observe(2,0), "Reset or mode change must not leave stale pixels");
        Check(!invalidator.ObserveContinuousMotion(false), "Static native scene must remain settled");
        for (var i=0;i<1000;i++) Check(invalidator.ObserveContinuousMotion(true), "Continuous native motion must keep painting");
        Check(invalidator.ObserveContinuousMotion(false), "Final native motion endpoint must paint once");
        for (var i=0;i<10000;i++) Check(!invalidator.ObserveContinuousMotion(false), "Completed native motion must settle without pet cels");
    }
}

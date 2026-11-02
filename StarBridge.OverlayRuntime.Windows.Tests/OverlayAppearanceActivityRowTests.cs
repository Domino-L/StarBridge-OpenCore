using System.Windows.Media;
namespace StarBridge.Desktop.Tests;
internal static class OverlayAppearanceActivityRowTests
{
    internal static void RunAll()
    {
        static void Check(bool condition,string text){if(!condition)throw new InvalidOperationException(text);}
        var at=DateTimeOffset.UtcNow;
        var row=new OverlayEventNotificationRow("fixture","content","time",Brushes.Blue,at.AddSeconds(20),OverlayEventNotificationTypes.LocationChange);
        Check(row.AppearanceActivity.Sequence==0,"Uncommitted row must not fabricate fresh activity");
        row.ConfigureMerge("fixture",OverlayLocationMergePhase.Provisional,at);
        var first=row.AppearanceActivity;
        Check(first.Sequence>0&&first.OccurredAt==at,"Committed row must keep original queued event age");
        row.BeginEnter(at,100);
        for(var t=0;t<=600;t+=10)row.AdvanceAnimation(at.AddMilliseconds(t),1);
        row.BeginBarrage(at,1,0);row.AdvanceBarrage(at.AddMilliseconds(200));
        row.CurrentDetail=_=>"updated current count";row.RefreshCurrentDetail([]);
        Check(row.AppearanceActivity==first,"Motion or refreshed counts must not fabricate new activity");
        row.MergeContent("confirmed","content","time",Brushes.Blue,OverlayLocationMergePhase.Confirmed,at.AddSeconds(1),at.AddSeconds(21));
        Check(row.AppearanceActivity.Sequence>first.Sequence&&row.AppearanceActivity.OccurredAt==at.AddSeconds(1),"Real merged event needs its own content-free activity revision");
        var merged=row.AppearanceActivity;
        row.BeginExit(at.AddSeconds(2),100);row.AdvanceAnimation(at.AddSeconds(3),1);row.CompleteMotionImmediately();
        Check(row.AppearanceActivity==merged,"Exit and removal must not fabricate activity");
        Console.WriteLine("PASS appearance activity rows: creation/merge advances; movement/detail refresh/removal do not");
    }
}

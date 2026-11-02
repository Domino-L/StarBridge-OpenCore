using System.Reflection;
using System.Windows.Media;
using StarBridge.Core.Presence;
namespace StarBridge.Desktop.Tests;
internal static class OverlayEventFinalFrameTests
{
    internal static void RunAll()
    {
        var at=DateTimeOffset.UtcNow;
        foreach(var count in new[]{1,2})
        {
            var settings=OverlayDisplaySettings.Default with{ShowEventNotifications=true,AnimationFrameRate=OverlayAnimationFrameRate.Fps60,EventNotificationMaxVisibleCount=2};
            var model=new OverlayViewModel(new OverlayAuthorizedRoster([]),settings,OverlayRosterSelectionSettings.Default,"en",false,
                new OverlayCommandState(null,null,null,null,null,null),PlayerPresenceKind.AppOnline,"",OverlaySceneContext.Local(settings.ScenePreference));
            try
            {
                model.EventNotifications.Clear();
                for(var i=0;i<count;i++)
                {
                    var row=new OverlayEventNotificationRow("fixture "+i,"content","time",Brushes.Blue,at.AddSeconds(30),OverlayEventNotificationTypes.MemberPresence);
                    row.ConfigureMerge(null,OverlayLocationMergePhase.None,at);row.BeginEnter(at,100);model.EventNotifications.Add(row);
                }
                var identities=model.EventNotifications.Select(row=>row.AppearanceActivity).ToArray();
                var tick=typeof(OverlayViewModel).GetMethod("TickEventNotifications",BindingFlags.Instance|BindingFlags.NonPublic)!;
                tick.Invoke(model,[at.AddMilliseconds(50)]);
                var before=model.EventNotificationAnimationFrame;var finalPublished=false;
                model.PropertyChanged+=(_,e)=>{if(e.PropertyName==nameof(model.EventNotificationAnimationFrame)&&model.EventNotifications.All(row=>!row.IsEntering&&row.RowOpacity==1&&row.MotionProgress==1))finalPublished=true;};
                tick.Invoke(model,[at.AddSeconds(2)]);
                if(model.EventNotificationAnimationFrame!=before+1||!finalPublished)throw new Exception("Completing the last entering row did not publish its exact settled snapshot");
                if(!model.EventNotifications.Select(row=>row.AppearanceActivity).SequenceEqual(identities))throw new Exception("Final paint fabricated new event activity");
                before=model.EventNotificationAnimationFrame;tick.Invoke(model,[at.AddSeconds(3)]);
                if(model.EventNotificationAnimationFrame!=before)throw new Exception("Settled rows keep publishing animation frames");
            }
            finally{model.ClearAuthorizedContent();}
        }
        Console.WriteLine("PASS event exact final snapshot: one/two simultaneous rows, settled opacity, no new activity or repeated quiet publication");
    }
}

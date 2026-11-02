using System.Reflection;
using StarBridge.Core.Presence;
namespace StarBridge.Desktop.Tests;

internal static class OverlayCommunicationAppearanceTests
{
    private static void Check(bool value,string text){if(!value)throw new InvalidOperationException(text);}
    private static readonly OverlayCommandState Empty=new("","",null,null,null,null);
    private static readonly OverlaySceneContext Context=new(OverlayScenePreference.PartyRoom,OverlaySceneKind.PartyRoom,"Fixture",false,RoomId:"fixture",ChatChannelId:"fixture");
    private static OverlayViewModel Create(OverlayDisplaySettings settings, IEnumerable<OverlayChatMessage>? messages=null,
        OverlayCommandState? command=null,OverlaySceneContext? context=null) => new(new([]),settings,OverlayRosterSelectionSettings.Default,
            "en",true,command??Empty,PlayerPresenceKind.AppOnline,"",context??Context,messages);
    private static void Refresh(OverlayViewModel model,OverlayDisplaySettings settings,IEnumerable<OverlayChatMessage> messages,
        OverlayCommandState? command=null,OverlaySceneContext? context=null) => model.Refresh(new([]),settings,OverlayRosterSelectionSettings.Default,
            "en",true,command??Empty,PlayerPresenceKind.AppOnline,"",context??Context,messages);
    private static OverlayChatMessage Message(long sequence, DateTimeOffset at,bool self=false,bool system=false) =>
        new(sequence,"fixture","Peer","Peer","Synthetic message",at,system,self,"#FFFFFF");
    internal static void RunAll()
    {
        foreach(var mode in new[]{OverlayChatDisplayMode.MessageList,OverlayChatDisplayMode.FullScreenBarrage})
        {
            var settings=OverlayDisplaySettings.Default with{ShowNotice=false,ShowChat=true,ChatDisplayMode=mode,ChatHideSelfMessages=true,ChatShowSystemMessages=false};
            var at=DateTimeOffset.UtcNow;
            var model=Create(settings,[Message(1,at.AddMinutes(-1))]);
            try
            {
                Check(model.CommunicationAppearanceActivities.Count==0,"Initial chat history is not fresh activity: "+mode);
                var cursor=new OverlayAppearanceActivityCursor();cursor.Observe([],1,true,at,0);
                Refresh(model,settings,[Message(1,at.AddMinutes(-1)),Message(2,at)]);
                var fresh=model.CommunicationAppearanceActivities.Single();
                Check(fresh.OccurredAt==at,"Chat keeps sender occurrence time instead of animation time");
                Check(cursor.Observe(model.CommunicationAppearanceActivities,1,true,at,100).Count==1,"One live chat admission reaches appearance metadata");
                for(var i=0;i<20;i++)Refresh(model,settings,[Message(1,at.AddMinutes(-1)),Message(2,at)]);
                Check(model.CommunicationAppearanceActivities.Single()==fresh,"Rebuilt list/pulse does not fabricate activity");
                Check(cursor.Observe(model.CommunicationAppearanceActivities,1,true,at,200).Count==0,"Repeated snapshots do not react twice");
                Refresh(model,settings,[Message(2,at),Message(3,at,true),Message(4,at,false,true)]);
                Check(model.CommunicationAppearanceActivities.Single()==fresh,"Filtered self/system messages do not react");
                Refresh(model,settings with{ShowChat=false},[]);
                Check(model.CommunicationAppearanceActivities.Count==0,"Disabled chat clears optional activity");
                Refresh(model,settings,[Message(5,at)]);
                Check(model.CommunicationAppearanceActivities.Count==0,"Enabling chat rebaselines old history");
                model.ClearAuthorizedContent();
                Check(model.CommunicationAppearanceActivities.Count==0,"Permission clear revokes optional metadata");
            }
            finally{model.ClearAuthorizedContent();}
        }
        Notice();
        BoundedListAndClock();
        PreviewBarrageMotionIsIndependentOfOrnaments();
        Console.WriteLine("PASS communication appearance: announcement baseline/dedup/original queue age, chat modes/history/filter/rebuild, bounded metadata and lifecycle");
    }
    private static void Notice()
    {
        var settings=OverlayDisplaySettings.Default with{ShowNotice=true,ShowChat=false};
        var context=Context with{Kind=OverlaySceneKind.Community};
        var command=Empty with{NoticeTitle="Notice",NoticeText="Original"};
        var model=Create(settings,command:command,context:context);
        try
        {
            Check(model.CommunicationAppearanceActivities.Count==0,"First fetched announcement is history, even when visible");
            Refresh(model,settings,[],command,context);
            Check(model.CommunicationAppearanceActivities.Count==0,"Renewed notice snapshot remains quiet");
            Refresh(model,settings,[],command with{NoticeText="Changed"},context);
            Check(model.CommunicationAppearanceActivities.Count==1,"Changed announcement is a fresh observation");
            var changed=model.CommunicationAppearanceActivities.Single();
            Refresh(model,settings,[],command with{NoticeText="Changed"},context);
            Check(model.CommunicationAppearanceActivities.Single()==changed,"Notice countdown/renewal retains one activity");
            model.ClearAuthorizedContent();
            Check(model.CommunicationAppearanceActivities.Count==0,"Permission clear revokes notice metadata");
            model.QueueCommunicationEvent("First","One");
            var first=model.CommunicationAppearanceActivities.Single();
            model.QueueCommunicationEvent("Second","Two");
            model.QueueCommunicationEvent("Second","Two");
            var pending=(System.Collections.ICollection)typeof(OverlayViewModel).GetField("_pendingCommunicationEvents",BindingFlags.NonPublic|BindingFlags.Instance)!.GetValue(model)!;
            Check(pending.Count==1,"Activity identity must not break content deduplication of queued announcements");
            var queued=((System.Collections.IEnumerable)pending).Cast<object>().Single();
            var original=(OverlayAppearanceActivity)queued.GetType().GetProperty("AppearanceActivity")!.GetValue(queued)!;
            Check(model.CommunicationAppearanceActivities.Single()==first,"Queued notice is not prematurely visible activity");
            typeof(OverlayViewModel).GetMethod("PromotePendingCommunicationEvent",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(model,null);
            Check(model.CommunicationAppearanceActivities.Single()==original,"Promotion does not mint a new timestamp or sequence");
            var cursor=new OverlayAppearanceActivityCursor();cursor.Observe([],1,true,first.OccurredAt,0);
            Check(cursor.Observe(model.CommunicationAppearanceActivities,1,true,original.OccurredAt.AddSeconds(6),6000).Count==0,"Older queued announcement cannot become a new reaction");
            model.ClearAuthorizedContent();
            var id=Guid.NewGuid();Check(model.TryShowLiveCommunicationEvent(id,"Live","Reminder"),"Live reminder admitted");
            Check(model.CommunicationAppearanceActivities.Count==1,"Fresh explicit reminder has one activity");
            model.ClearLiveCommunicationEvent(Guid.NewGuid());Check(model.CommunicationAppearanceActivities.Count==1,"Unrelated reminder close preserves current activity");
            model.ClearLiveCommunicationEvent(id);Check(model.CommunicationAppearanceActivities.Count==0,"Owner close clears current activity");
        }
        finally{model.ClearAuthorizedContent();}
    }
    private static void BoundedListAndClock()
    {
        var settings=OverlayDisplaySettings.Default with{ShowNotice=false,ShowChat=true,ChatDisplayMode=OverlayChatDisplayMode.MessageList};
        var at=DateTimeOffset.UtcNow;var model=Create(settings);
        try
        {
            Refresh(model,settings,Enumerable.Range(1,1000).Select(i=>Message(i,at.AddMinutes(-1))));
            Check(model.CommunicationAppearanceActivities.Count==128,"Appearance metadata remains bounded independently of chat history");
            var cursor=new OverlayAppearanceActivityCursor();cursor.Observe([],1,true,at.AddMinutes(-2),0);
            Check(cursor.Observe(model.CommunicationAppearanceActivities,1,true,at,120000).Count==0,"Late fetched messages keep original old age");
            Refresh(model,settings,[Message(1001,at.AddDays(1))]);
            Check(cursor.Observe(model.CommunicationAppearanceActivities,1,true,at,120001).Count==0,"Future peer time is not accepted as live activity");
        }
        finally{model.ClearAuthorizedContent();}
    }

    private static void PreviewBarrageMotionIsIndependentOfOrnaments()
    {
        var at=DateTimeOffset.UtcNow;
        var off=OverlayDisplaySettings.Default with {ShowNotice=false,ShowChat=true,
            ChatDisplayMode=OverlayChatDisplayMode.FullScreenBarrage,
            AnimationFrameRate=OverlayAnimationFrameRate.Off};
        // Normal Open keeps its existing explicit Off semantics. Only the
        // temporary appearance-preview ViewModel opts into reading movement.
        foreach(var preserve in new[]{false,true})
        {
            var model=Create(off);
            try
            {
                Check(!model.PreserveBarrageMotion,"A new normal ViewModel inherits no preview policy");
                model.PreserveBarrageMotion=preserve;
                Refresh(model,off,[Message(1,at)]);
                var row=model.ChatMessages.Single();
                Check(row.IsBarrageActive==preserve,"Preview can preserve barrage movement without enabling ornament motion");
                Check(!row.IsEntering,"Decorative entry remains static under Off");
                var originalActivity=model.CommunicationAppearanceActivities.Single();
                var start=row.BarrageStartedAtUtc;
                Refresh(model,off with{AnimationFrameRate=OverlayAnimationFrameRate.Fps60},[Message(1,at)]);
                Refresh(model,off,[Message(1,at)]);
                Check(ReferenceEquals(model.ChatMessages.Single(),row)&&row.BarrageStartedAtUtc==start,
                    "Presentation settings do not restart or replace a current barrage");
                Check(model.CommunicationAppearanceActivities.Single()==originalActivity,
                    "Motion settings do not fabricate another pet activity");
                var end=preserve?start.AddSeconds(row.BarrageDurationSeconds+.01):row.ExpiresAt.AddMilliseconds(1);
                typeof(OverlayViewModel).GetMethod("TickChatMessages",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(model,[end]);
                Check(model.ChatMessages.Count==0,"Both normal static and preview moving rows retire by their normal deadlines");
                Refresh(model,off with{ChatDisplayMode=OverlayChatDisplayMode.MessageList},[Message(2,at)]);
                Check(model.ChatMessages.All(item=>!item.IsBarrageActive&&!item.IsEntering),
                    "Essential barrage policy does not enable message-list or event decoration animation");
            }
            finally{model.ClearAuthorizedContent();}
        }
        Console.WriteLine("PASS preview essential barrage: Off ornaments, normal isolation, same row/timeline/activity and retirement");
    }
}

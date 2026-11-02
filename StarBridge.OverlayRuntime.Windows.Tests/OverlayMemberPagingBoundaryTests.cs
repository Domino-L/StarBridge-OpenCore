using System.Collections;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using Rect=System.Windows.Rect;

namespace StarBridge.Desktop.Tests;

internal static class OverlayMemberPagingBoundaryTests
{
    private const string Shard="pub_use1_fixture_001";
    private static readonly BindingFlags All=BindingFlags.Instance|BindingFlags.Static|BindingFlags.Public|BindingFlags.NonPublic;
    private static int _failures;
    private static string _output="";
    internal static void RunAll()
    {
        _failures=0;
        var root=Path.Combine(AppContext.BaseDirectory,"member-paging-boundaries");
        foreach(var name in new[]{"evidence","revocation","bounds"}) {
            _output=Path.Combine(root,name);Directory.CreateDirectory(_output);
            try { switch(name){case "evidence":Evidence();break;case "revocation":Revocation();break;case "bounds":Bounds();break;} }
            catch(Exception error){_failures++;Print(new{Kind="HARNESS_ERROR",Case=name,Error=error.ToString()});}
        }
        if(_failures!=0) throw new InvalidOperationException($"Member boundary regression failures: {_failures}");
        Console.WriteLine("PASS member paging evidence, authorization and bounded indicator regressions");
    }
    private static string Hash(byte[] data)=>Convert.ToHexString(SHA256.HashData(data));
    private static void Print(object value)=>Console.WriteLine(JsonSerializer.Serialize(value));
    private static void Check(bool value,string name,object evidence){if(!value)_failures++;Print(new{Kind="CHECK",Name=name,Status=value?"PASS":"FAIL",Evidence=evidence});}
    private static object? Call(object target,string name,params object?[] values)=>target.GetType().GetMethods(All).Single(method=>method.Name==name&&method.GetParameters().Length==values.Length).Invoke(target,values);
    private static object? Get(object target,string name)=>target.GetType().GetField(name,All)?.GetValue(target)??target.GetType().GetProperty(name,All)!.GetValue(target);
    private static void Set(object target,string name,object? value){if(target.GetType().GetField(name,All)is{}field)field.SetValue(target,value);else target.GetType().GetProperty(name,All)!.SetValue(target,value);}
    private static object State(OverlayCompositionHudWindow window)=>Call(window,"BuildFrameState")!;
    private static object[] Rows(object state)=>((IEnumerable)Get(state,"MemberRows")!).Cast<object>().ToArray();
    private static string[] Keys(IEnumerable rows)=>rows.Cast<object>().Select(row=>(string?)Get(row,"Key")??"<null>").ToArray();
    private static PlayerRow Player(string id,string? shard=Shard,string? location="Orison",string live="InGame")=>new(
        id,"Online","Carrack","Ship: Carrack",location??"Unknown",Callsign:id,RawLocation:location??"Unknown",ServerShard:shard,LiveStatus:live,AccountId:id,
        SharedOnlineStatus:"Online",SharedLiveStatus:live,SharedShip:"Carrack",SharedLocation:location);
    private static IReadOnlyList<(PlayerRow Player,bool SameServer,bool SameLocation,bool Online)> Classify(PlayerRow player)=>
        OverlayRosterPlanner.ClassifyMembers(new([player]),new OverlayRosterViewport(180,Shard,"Orison"));
    private static void Evidence()
    {
        var now=DateTimeOffset.UnixEpoch;
        foreach(var visible in new[]{true,false}){
            var tracker=new OverlayMemberPagingTracker();var keys=new HashSet<string>(visible?["peer"]:[],StringComparer.OrdinalIgnoreCase);
            tracker.Observe(Classify(Player("peer",null,null)),keys,true,now);
            tracker.Observe(Classify(Player("peer")),keys,true,now.AddSeconds(1));
            var pages=new Dictionary<string,int>{{"peer",1}};
            var cue=tracker.CueStartedAt("peer",now.AddSeconds(1.1));var pending=tracker.PendingPages(pages,0);
            Check(cue is null&&pending.Count==0,"initial unknown evidence completion must not invent member change",new{Visible=visible,Cue=cue,Pending=pending});
        }
        var paused=new OverlayMemberPagingTracker();var none=new HashSet<string>();
        paused.Observe(Classify(Player("peer")),none,true,now);
        paused.Observe(Classify(Player("peer",live:"Paused")),none,true,now.AddSeconds(1));
        paused.Observe(Classify(Player("peer")),none,true,now.AddSeconds(2));
        var pendingPaused=paused.PendingPages(new Dictionary<string,int>{{"peer",1}},0);
        Check(pendingPaused.Count==0,"paused synchronization recovery is not a fresh game entry",new{Pending=pendingPaused});
        ProjectedPauseAndOfflineControls();
        KnownChangeAndGapControls();
    }
    private static void ProjectedPauseAndOfflineControls()
    {
        foreach(var room in new[]{false,true})foreach(var visible in new[]{false,true})
        {
            PlayerRow Project(string presence)
            {
                var content=new InformationOverlayRoomContent("pause-room","Room","",4,"",[new("Peer","Peer",false,presence,"Orison","Carrack","US")],[]);
                var community=new InformationOverlayCommunityContent("pause-community","Community",[new("Peer","Peer","Member",presence,Ship:"Carrack",Location:"Orison",ServerRegion:"US",IsSelf:false)]);
                return NativeInformationOverlayRuntime.ProjectSource(room?content:null,room?null:community,OverlayScenePreference.Auto,"zh").Scene.Players.Single() with{AccountId="peer"};
            }
            var keys=new HashSet<string>(visible?["peer"]:[]);var map=new Dictionary<string,int>{{"peer",1}};
            var now=DateTimeOffset.UnixEpoch;var paused=Project("Paused");
            Check(paused.SharedPresence==PlayerPresenceKind.Offline,"projected pause remains visibly offline",new{Room=room,paused.LiveStatus,paused.SharedLiveStatusValue,paused.SharedPresence});
            Check(paused.PresenceText=="离线"&&paused.SharedPresenceText=="离线"&&!PlayerPresence.IsOnline(paused.SharedPresence)&&
                paused.SharedShipDisplayText==PlayerSessionStatePresentation.NotInGame&&paused.SharedLocationDisplayText==PlayerSessionStatePresentation.NotInGame,
                "paused raw fact does not expose live shared presence, ship or location",new{Room=room,paused.PresenceText,paused.SharedPresenceText,paused.SharedShipDisplayText,paused.SharedLocationDisplayText});
            Check(Project("Offline").SharedLiveStatusValue=="Offline","true projected offline stays raw offline",new{Room=room});
            var tracker=new OverlayMemberPagingTracker();tracker.Observe(Classify(Project("InGame")),keys,true,now);
            tracker.Observe(Classify(paused),keys,true,now.AddSeconds(1));tracker.Observe(Classify(Project("InGame")),keys,true,now.AddSeconds(2));
            Check(tracker.CueStartedAt("peer",now.AddSeconds(2.1)) is null&&tracker.PendingPages(map,0).Count==0,
                "actual projected pause recovery does not invent cue or pending",new{Room=room,Visible=visible,Pending=tracker.PendingPages(map,0),Cue=tracker.CueStartedAt("peer",now.AddSeconds(2.1))});
            var real=new OverlayMemberPagingTracker();real.Observe(Classify(Project("Offline")),keys,true,now);
            real.Observe(Classify(Project("InGame")),keys,true,now.AddSeconds(1));
            Check(visible?real.CueStartedAt("peer",now.AddSeconds(1.1)) is not null:real.PendingPages(map,0).SequenceEqual([1]),
                "real projected offline-to-game entry still cues or marks pending",new{Room=room,Visible=visible});
            if(!room&&!visible)
            {
                var source=NativeInformationOverlayRuntime.ProjectSource(null,new InformationOverlayCommunityContent("pause-community","Community",[]),OverlayScenePreference.Auto,"zh");
                var settings=OverlayDisplaySettings.Default with{ShowEventNotifications=true,EventNotificationTypes=OverlayEventNotificationTypes.OnlineSummary,AnimationFrameRate=OverlayAnimationFrameRate.Off};
                var model=new OverlayViewModel(new([Project("InGame")]),settings,OverlayRosterSelectionSettings.Default,"zh",true,source.Command,PlayerPresenceKind.InGame,Shard,source.Scene.Context);
                try
                {
                    model.EventNotifications.Clear();
                    void Refresh(string state)=>model.Refresh(new([Project(state)]),settings,OverlayRosterSelectionSettings.Default,"zh",true,source.Command,PlayerPresenceKind.InGame,Shard,source.Scene.Context);
                    int Count()=>model.EventNotifications.Count(row=>row.EventType!=OverlayEventNotificationTypes.None)+model.PendingEventNotificationCount;
                    Refresh("Paused");Refresh("InGame");Check(Count()==0,"projected pause does not spam the actual online event rail",new{Cards=Count()});
                    Refresh("Offline");Check(Count()==1,"actual projected offline exit is announced once",new{Cards=Count()});
                    Refresh("InGame");Refresh("InGame");Check(Count()==2,"actual projected return is announced once",new{Cards=Count()});
                }finally{model.ClearAuthorizedContent();}
            }
        }
    }
    private static void KnownChangeAndGapControls()
    {
        var now=DateTimeOffset.UnixEpoch;var visible=new HashSet<string>{"peer"};
        foreach(var changed in new[]{Player("peer",location:"Lorville"),Player("peer") with{RawShip="Hornet",Ship="Hornet",SharedShip="Hornet"},Player("peer",live:"Offline")})
        {
            var tracker=new OverlayMemberPagingTracker();tracker.Observe(Classify(Player("peer")),visible,true,now);tracker.Observe(Classify(changed),visible,true,now.AddSeconds(1));
            Check(tracker.CueStartedAt("peer",now.AddSeconds(1.1)) is not null,"known location/ship/real presence changes keep their cue",new{changed.SharedLocation,changed.SharedShip,changed.LiveStatus});
        }
        var gaps=new OverlayMemberPagingTracker();gaps.Observe(Classify(Player("peer")),visible,true,now);
        gaps.Observe(Classify(Player("peer",null,null) with{Ship="Unknown",RawShip="Unknown",SharedShip=null}),visible,false,now.AddSeconds(1),false);
        var last=((IDictionary)Get(gaps,"_last")!)["peer"]!;
        Check((string)Get(last,"Location")! == "Orison"&&(string)Get(last,"Ship")! == "Carrack"&&(string)Get(last,"Shard")! == Shard,
            "missing comparison data does not erase previously recognized facts",new{Location=Get(last,"Location"),Ship=Get(last,"Ship"),Shard=Get(last,"Shard")});
        gaps.Observe(Classify(Player("peer")),visible,true,now.AddSeconds(2));
        Check(gaps.CueStartedAt("peer",now.AddSeconds(2.1)) is null,"known-gap-known recovery does not invent a cue",new{});
        var local=new OverlayMemberPagingTracker();var tuple=new[]{(Player("peer"),SameServer:false,SameLocation:false,Online:true)};
        local.Observe(tuple,visible,false,now,false);local.Observe(Classify(Player("peer")),visible,true,now.AddSeconds(1));
        Check(local.CueStartedAt("peer",now.AddSeconds(1.1)) is null,"first local relationship evidence is not a member movement",new{});
        var unknown=new OverlayMemberPagingTracker();unknown.Observe(Classify(Player("peer")),visible,true,now);
        unknown.Observe(Classify(Player("peer",location:"Lorville") with{RealtimeStateUnknown=true}),visible,true,now.AddSeconds(1));
        unknown.Observe(Classify(Player("peer")),visible,true,now.AddSeconds(2));
        Check(unknown.CueStartedAt("peer",now.AddSeconds(2.1)) is null,"unknown realtime state is not authority to cue recovered facts",new{});
    }
    private static (OverlayCompositionHudWindow Window,OverlayViewModel Model,OverlayDisplaySettings Settings,OverlayRosterSelectionSettings Selection,OverlayLayoutItem[] Layout,OverlaySceneContext Context,OverlayCommandState Command) Create(string scope,PlayerRow[] rows,int rowLimit=3)
    {
        var source=NativeInformationOverlayRuntime.ProjectSource(null,new InformationOverlayCommunityContent(scope,scope,[]),OverlayScenePreference.Auto,"zh");
        var settings=OverlayDisplaySettings.Default with{EnableStartupTransition=false,ShowEventNotifications=false,AnimationFrameRate=OverlayAnimationFrameRate.Fps60};
        var selection=new OverlayRosterSelectionSettings(OverflowMode:OverlayRosterOverflowMode.Rotate,UserRowLimit:rowLimit);
        var layout=OverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload).ToArray();
        var window=new OverlayCompositionHudWindow(new(rows),[],layout,settings,selection,"zh",true,source.Command,PlayerPresenceKind.InGame,Shard,
            new Rect(0,0,640,480),OverlayStartupTransitionContext.ForLanguage("zh"),source.Scene.Context);
        var model=(OverlayViewModel)Get(window,"_viewModel")!;model.ApplyMemberViewport(52+rowLimit*35);
        return(window,model,settings,selection,layout,source.Scene.Context,source.Command);
    }
    private static void Revocation()
    {
        var fixture=Create("source-A",Enumerable.Range(1,9).Select(i=>Player($"A-{i:00}")).ToArray());
        using var renderer=fixture.Window;var before=State(renderer);
        Call(fixture.Model,"AdvanceMemberPage");var after=State(renderer);Call(renderer,"ObserveMemberFlip",before,after);
        var outgoing=Keys((IEnumerable)Get(renderer,"_memberFlipOutgoing")!);
        Check(outgoing.Length>0&&outgoing.All(key=>key.StartsWith("A-")),"control: actual page flip captured source A outgoing rows",new{Outgoing=outgoing});
        renderer.ClearAuthorizedContent();var revoked=State(renderer);Call(renderer,"ObserveMemberFlip",after,revoked);
        Check(Rows(revoked).Length==0,"actual ClearAuthorizedContent clears new member snapshot",new{Rows=Rows(revoked).Length});
        var afterClear=Keys((IEnumerable)Get(renderer,"_memberFlipOutgoing")!);
        Check(afterClear.Length==0,"revocation clears renderer outgoing rows",new{Outgoing=afterClear,PreviousSequence=Get(Get(after,"MemberPaging")!,"FlipSequence"),NextSequence=Get(Get(revoked,"MemberPaging")!,"FlipSequence")});
        var b=NativeInformationOverlayRuntime.ProjectSource(null,new InformationOverlayCommunityContent("source-B","source-B",[]),OverlayScenePreference.Auto,"zh");
        renderer.RefreshWithDpi(new OverlayAuthorizedRoster(Enumerable.Range(1,3).Select(i=>Player($"B-{i:00}")).ToArray()),[],fixture.Layout,fixture.Settings,fixture.Selection,"zh",true,b.Command,
            PlayerPresenceKind.InGame,Shard,new Rect(0,0,640,480),OverlayStartupTransitionContext.ForLanguage("zh"),b.Scene.Context);
        var next=State(renderer);Call(renderer,"ObserveMemberFlip",revoked,next);
        Check(Rows(next).Length>0&&Keys(Rows(next)).All(key=>key.StartsWith("B-")),"control: new actual snapshot contains only B",new{Rows=Keys(Rows(next))});
        // Real WARP panel drawing; clock positioned in the outgoing phase in
        // both draws. Only the cached outgoing list changes for the control.
        InitDrawing(renderer);
        if((DateTimeOffset)Get(renderer,"_memberFlipStartedAtUtc")! != DateTimeOffset.MinValue) Set(renderer,"_memberFlipStartedAtUtc",DateTimeOffset.UtcNow.AddMilliseconds(-50));
        var withCache=Render(renderer,next,640,480,"A-to-B-cached.png");
        var outgoingField=renderer.GetType().GetField("_memberFlipOutgoing",All)!;
        outgoingField.SetValue(renderer,Activator.CreateInstance(typeof(List<>).MakeGenericType(outgoingField.FieldType.GenericTypeArguments[0])));
        Set(renderer,"_memberFlipStartedAtUtc",DateTimeOffset.MinValue);
        var withoutCache=Render(renderer,next,640,480,"A-to-B-no-outgoing-control.png");
        var differs=!withCache.SequenceEqual(withoutCache);
        Check(!afterClear.Any(key=>key.StartsWith("A-"))&&!differs,"source switch must not paint A after new B snapshot",new{OldOutgoing=afterClear,PixelBuffersDifferent=differs,WithCache=Hash(withCache),WithoutCache=Hash(withoutCache),Boundary="actual VM clear+refresh+BuildFrameState and shipping ObserveMemberFlip/DrawMembersPanel; offscreen, not DComp"});
        Call(renderer,"DisposeOnRenderThread");
        AuthorizationAndMotionControls();
    }
    private static void AuthorizationAndMotionControls()
    {
        foreach(var mode in new[]{"clear-empty","same-source-recovery","direct-source-switch","animation-off","animation-finished"})
        {
            var fixture=Create("control-A",Enumerable.Range(1,9).Select(i=>Player($"A-{i:00}")).ToArray());
            using var renderer=fixture.Window;var before=State(renderer);Call(fixture.Model,"AdvanceMemberPage");var after=State(renderer);Call(renderer,"ObserveMemberFlip",before,after);
            Check(Keys((IEnumerable)Get(renderer,"_memberFlipOutgoing")!).Length>0,"same-source real page flip still animates",new{Mode=mode});
            if(mode=="animation-finished")
            {
                Set(renderer,"_state",after);Set(renderer,"_memberFlipStartedAtUtc",DateTimeOffset.UtcNow.AddSeconds(-5));
                Check(!(bool)Call(renderer,"IsMemberMotionActive")!,"completed page animation stops motion",new{});
            }
            else if(mode=="clear-empty") {renderer.ClearAuthorizedContent();Call(renderer,"ObserveMemberFlip",after,State(renderer));}
            else
            {
                var scope=mode=="direct-source-switch"?"control-B":"control-A";
                if(mode=="same-source-recovery")renderer.ClearAuthorizedContent();
                var source=NativeInformationOverlayRuntime.ProjectSource(null,new InformationOverlayCommunityContent(scope,scope,[]),OverlayScenePreference.Auto,"zh");
                var settings=mode=="animation-off"?fixture.Settings with{AnimationFrameRate=OverlayAnimationFrameRate.Off}:fixture.Settings;
                renderer.RefreshWithDpi(new(Enumerable.Range(1,9).Select(i=>Player($"B-{i:00}")).ToArray()),[],fixture.Layout,settings,fixture.Selection,"zh",true,source.Command,
                    PlayerPresenceKind.InGame,Shard,new Rect(0,0,640,480),OverlayStartupTransitionContext.ForLanguage("zh"),source.Scene.Context);
                Call(renderer,"ObserveMemberFlip",after,State(renderer));
            }
            Check(Keys((IEnumerable)Get(renderer,"_memberFlipOutgoing")!).Length==0&&(DateTimeOffset)Get(renderer,"_memberFlipStartedAtUtc")! == DateTimeOffset.MinValue,
                "authorization, source or finished motion invalidates outgoing content and clock",new{Mode=mode});
        }
        var local=Create("device-local",[Player("peer")]);using var localRenderer=local.Window;
        var enabled=local.Settings with{ShowEventNotifications=true,EventNotificationTypes=OverlayEventNotificationTypes.OnlineSummary};
        local.Model.Refresh(new([Player("peer")]),enabled,local.Selection,"zh",true,local.Command,PlayerPresenceKind.InGame,Shard,local.Context);
        local.Model.EventNotifications.Clear();
        local.Model.QueueGameEventNotification(OverlayEventNotificationTypes.OnlineSummary,"device-local-fixture","local",false,true,isDeviceLocal:true);
        Check(local.Model.EventNotifications.Any(row=>row.Title=="device-local-fixture"),"control: local event queued",new{});
        local.Model.ClearAuthorizedContent(preserveDeviceLocalEvents:true);
        Check(local.Model.EventNotifications.Any(row=>row.Title=="device-local-fixture"),"member authorization reset preserves device-local event policy",new{});
    }
    private static void Bounds()
    {
        Check(OverlayMemberPageIndicatorLayout.Resolve(0,1,192).Width==0,"single page still hides the indicator",new{});
        foreach(var index in new[]{0,1,2})
        {
            var small=OverlayMemberPageIndicatorLayout.Resolve(index,3,192);
            Check(small.Width==66&&small.LabelWidth==26&&small.Pages.SequenceEqual(new int?[]{0,1,2}),"standard three-page geometry stays unchanged",new{Index=index,small.Width,small.Pages});
        }
        var tiny=OverlayMemberPageIndicatorLayout.Resolve(20,50,28);
        Check(tiny.Pages.Count==0&&tiny.Label=="21/50"&&tiny.Width<=28,"very narrow header keeps only current and total page text",new{tiny.Width,tiny.Label});
        foreach(var count in new[]{50,250})foreach(var page in new[]{0,count/2,count-1})foreach(var available in new[]{0.5f,28,80,136,272})
        {
            var layout=OverlayMemberPageIndicatorLayout.Resolve(page,count,available,44);
            Check(layout.Width<=available&&layout.Pages.Count<=9&&layout.Pages.Where(value=>value.HasValue).All(value=>value>=0&&value<count)&&
                (layout.Pages.Count==0||layout.Pages.Contains(page)),"bounded current-page window remains in budget",new{Count=count,Page=page,Available=available,layout.Width,layout.Pages});
        }
        foreach(var size in new[]{100,500})foreach(var width in new[]{240,320,480}){
            var fixture=Create("bounds",Enumerable.Range(1,size).Select(i=>Player($"member-{i:000}")).ToArray(),2);
            using var renderer=fixture.Window;var state=State(renderer);
            var geometry=InformationOverlayLayoutGeometry.ResolveItemRect(new InformationOverlayLayoutItem("Members",24d/640,24d/480,width/640d,140d/480),640,480);
            var rect=new Rect(geometry.Left,geometry.Top,geometry.Width,geometry.Height);Set(state,"MembersRect",rect);
            var indicator=(float)Call(renderer,"MemberPageIndicatorWidth",state)!;
            var right=(float)rect.Right-28;var start=right-indicator;var titleLeft=(float)rect.Left+20;
            Check(start>=titleLeft,"page indicator fits allowed member panel and leaves header space",new{Members=size,PanelWidth=width,PageCount=Get(Get(state,"MemberPaging")!,"PageCount"),IndicatorWidth=indicator,IndicatorLeft=start,PanelLeft=rect.Left,TitleLeft=titleLeft,AvailableHeaderWidth=right-titleLeft,LayoutMinWidth=240});
            if(width==240){InitDrawing(renderer);var moving=Render(renderer,state,640,220,$"bounds-{size}-{width}.png");Set(state,"AnimationFrameRate",OverlayAnimationFrameRate.Off);
                var off=Render(renderer,state,640,220,$"bounds-{size}-{width}-off.png");Check(moving.SequenceEqual(off),"animation Off preserves the static bounded indicator",new{Members=size,PanelWidth=width});Call(renderer,"DisposeOnRenderThread");}
        }
    }
    private static void InitDrawing(OverlayCompositionHudWindow renderer)
    {
        var d3d=D3D11.D3D11CreateDevice(DriverType.Warp,DeviceCreationFlags.BgraSupport,[Vortice.Direct3D.FeatureLevel.Level_11_0]);
        var dxgi=d3d.QueryInterface<IDXGIDevice>();var factory=D2D1.D2D1CreateFactory<ID2D1Factory1>(Vortice.Direct2D1.FactoryType.SingleThreaded);
        var device=factory.CreateDevice(dxgi);var context=device.CreateDeviceContext(DeviceContextOptions.None);
        Set(renderer,"_d3dDevice",d3d);Set(renderer,"_dxgiDevice",dxgi);Set(renderer,"_d2dFactory",factory);Set(renderer,"_d2dDevice",device);Set(renderer,"_d2dDeviceContext",context);
        Call(renderer,"CreateStrokeStyles");Set(renderer,"_writeFactory",DWrite.DWriteCreateFactory<IDWriteFactory>(Vortice.DirectWrite.FactoryType.Shared));Call(renderer,"CreateTextFormats");
    }
    private static byte[] Render(OverlayCompositionHudWindow renderer,object state,int width,int height,string file)
    {
        var target=(ID2D1DeviceContext)Get(renderer,"_d2dDeviceContext")!;target.SetDpi(96,96);
        var format=new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm,Vortice.DCommon.AlphaMode.Premultiplied);
        using var bitmap=target.CreateBitmap(new SizeI(width,height),IntPtr.Zero,0,new BitmapProperties1(format,96,96,BitmapOptions.Target));target.Target=bitmap;
        var brushes=renderer.GetType().GetField("_frameBrushes",All)!;brushes.SetValue(renderer,Activator.CreateInstance(brushes.FieldType));
        target.BeginDraw();target.Clear(new Color4(0,0,0,0));Call(renderer,"DrawMembersPanel",target,state);target.EndDraw().CheckError();target.Target=null;Call(renderer,"DisposeFrameBrushes");
        using var read=target.CreateBitmap(new SizeI(width,height),IntPtr.Zero,0,new BitmapProperties1(format,96,96,BitmapOptions.CpuRead|BitmapOptions.CannotDraw));read.CopyFromBitmap(bitmap);
        var mapped=read.Map(MapOptions.Read);var pixels=new byte[width*height*4];try{for(var y=0;y<height;y++)Marshal.Copy(mapped.Bits+y*(int)mapped.Pitch,pixels,y*width*4,width*4);}finally{read.Unmap();}
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(width,height,96,96,PixelFormats.Pbgra32,null,pixels,width*4)));using var stream=File.Create(Path.Combine(_output,file));encoder.Save(stream);return pixels;
    }
}

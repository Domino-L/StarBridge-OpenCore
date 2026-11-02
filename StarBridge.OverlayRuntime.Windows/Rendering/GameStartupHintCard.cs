namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

/// <summary>Independent silent launch choreography; one clock, no web view or game input.</summary>
internal sealed class GameStartupHintCard : FrameworkElement
{
    internal const double CardHeight=62, TravelLeft=80, TravelTop=64, OffscreenRight=16;
    internal const int ReadAt=2200, ExitAt=6700, Total=8000;
    internal static readonly MeteorTimeline Timeline=new();
    private readonly bool _light;
    private readonly BitmapSource _mark,_star;
    private readonly FormattedText _brand,_prefix,_binding,_suffix;
    private readonly Stopwatch _clock=new();
    private readonly DispatcherTimer _timer;
    private Action? _completed;
    private bool _animated,_active;
    private double _time=ReadAt;
    internal double VisibleWidth {get;}
    internal string Binding {get;}
    internal bool PlaybackActive=>_active;
    internal double PlaybackTime=>_time;

    internal GameStartupHintCard(DesktopNotification notice)
    {
        Binding=(notice.GameStartupHint??throw new ArgumentException("Startup hint required.")).Binding;
        var en=notice.Locale.StartsWith("en",StringComparison.OrdinalIgnoreCase);
        var tw=notice.Locale is "zh-TW" or "zh-HK" or "zh-Hant";
        _light=notice.Appearance=="light";
        var foreground=Paint(_light?"#17242C":"#F3F8FF");var secondary=Paint(_light?"#4A5B64":"#CEE0F8");
        _brand=Text(en?"StarBridge":tw?"星海艦橋":"星海舰桥",14,foreground,true);
        _prefix=Text(en?"Press ":"按 ",12,secondary);
        _binding=Text(Binding,12,foreground,true,"Consolas");
        _suffix=Text(en?" to open menu":tw?" 呼出選單":" 呼出菜单",12,secondary);
        // Keep the approved normal size; custom bindings/locales must remain fully readable.
        VisibleWidth=Math.Max(260,Math.Ceiling(66+_prefix.WidthIncludingTrailingWhitespace+_binding.Width+12+_suffix.WidthIncludingTrailingWhitespace+8));
        Width=TravelLeft+VisibleWidth+OffscreenRight;Height=TravelTop*2+CardHeight;
        IsHitTestVisible=false;Focusable=false;
        RenderOptions.SetBitmapScalingMode(this,BitmapScalingMode.HighQuality);
        _mark=Image("startup_meteor_mark");_star=Image("startup_meteor_star");
        _timer=new DispatcherTimer(DispatcherPriority.Render,Dispatcher){Interval=TimeSpan.FromMilliseconds(16)};
        _timer.Tick+=(_,_)=>Tick();Unloaded+=(_,_)=>Stop();
        System.Windows.Automation.AutomationProperties.SetName(this,en?$"StarBridge is ready. Press {Binding} to open the menu.":tw?$"星海艦橋已就緒，按 {Binding} 呼出選單。":$"星海舰桥已就绪，按 {Binding} 呼出菜单。");
    }
    internal void BeginPresentation(bool animated,Action completed)
    {
        Stop();_completed=completed;_animated=animated;_active=true;_clock.Restart();_time=animated?0:ReadAt;
        InvalidateVisual();_timer.Interval=TimeSpan.FromMilliseconds(animated?16:4500);_timer.Start();
    }
    private void Tick()
    {
        if(!_active)return;
        if(!_animated||_clock.Elapsed.TotalMilliseconds>=Total){var done=_completed;Stop();_time=Total;InvalidateVisual();done?.Invoke();return;}
        _time=_clock.Elapsed.TotalMilliseconds;InvalidateVisual();
        // Sleep through the static reading interval; frame updates only during choreography.
        _timer.Interval=TimeSpan.FromMilliseconds(_time is >=ReadAt and <ExitAt?Math.Max(1,ExitAt-_time):16);
    }
    internal void Stop(){_active=false;_timer.Stop();_clock.Stop();_completed=null;}
    internal void SeekForTest(double time){Stop();_time=Math.Clamp(time,0,Total);InvalidateVisual();}
    internal static System.Drawing.Rectangle Placement(System.Drawing.Rectangle game,uint dpi,double visibleWidth)
    {
        if(game.Width<=0||game.Height<=0||!double.IsFinite(visibleWidth)||visibleWidth<260)throw new ArgumentException("Invalid startup hint area.");
        var scale=Math.Clamp(dpi/96d,.5,4);
        var width=(int)Math.Ceiling((TravelLeft+visibleWidth+OffscreenRight)*scale);
        var height=(int)Math.Ceiling((TravelTop*2+CardHeight)*scale);
        // Reserve the top-right corner for driver/recording prompts; all values are client-relative.
        var cardTop=Math.Min(160*scale,Math.Max(0,game.Height-(CardHeight+16)*scale));
        return new(game.Right-width+(int)Math.Ceiling(OffscreenRight*scale),game.Top+(int)Math.Round(cardTop-TravelTop*scale),width,height);
    }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);dc.PushTransform(new TranslateTransform(TravelLeft,TravelTop));DrawPanel(dc);DrawScan(dc);
        var positions=new[]{new Point(4,46),new Point(30,38),new Point(-6,24),new Point(52,52)};var widths=new[]{30d,20,26,36};
        for(var i=0;i<4;i++){var state=Timeline.Sample(".c-m"+(i+1),_time);if(state.Opacity<=0)continue;Push(dc,state,positions[i],new(widths[i]/2,.5));dc.DrawRoundedRectangle(TailBrush(),null,new(0,0,widths[i],i==3?1.5:1),.5,.5);Pop(dc);}
        dc.PushTransform(new TranslateTransform(3,3));
        DrawTrail(dc,".c-nw","150,575 501,349 504,377 225,576",-9.8,24.4,18,-33);
        DrawTrail(dc,".c-se","750,913 1035,686 1106,687 771,922",15.3,39.3,18,-35);
        DrawTrail(dc,".c-sw","55,938 465,682 521,716 66,951",-19.4,40.5,22,-32);
        DrawTrail(dc,".c-ne","746,555 1194,334 1198,355 797,586",13.7,24.2,20,-26);
        var star=Timeline.Sample(".c-star",_time);
        if(star.Opacity>0){Push(dc,star,new(0,0),new(28,28));DrawBrandImage(dc,_star);Pop(dc);}
        var glint=Timeline.Sample(".c-glint",_time);
        glint=glint with {Opacity=glint.Opacity*.35};
        if(glint.Opacity>0){Push(dc,glint,new(8,8),new(20,20));dc.DrawRectangle(FlashBrush(0),null,new(0,19.25,40,1.5));dc.DrawRectangle(FlashBrush(90),null,new(19.25,6,1.5,28));Pop(dc);}
        dc.Pop();dc.Pop();
    }
    private void DrawPanel(DrawingContext dc)
    {
        var state=Timeline.Sample(".c-card",_time);var width=VisibleWidth+OffscreenRight;
        dc.PushClip(new RectangleGeometry(new Rect(width*state.Left,0,Math.Max(0,width*(1-state.Left-state.Right)),CardHeight)));
        var panel=Geometry.Parse(FormattableString.Invariant($"M 10,0 H {width} V 62 H 10 Q 0,62 0,52 V 10 Q 0,0 10,0 Z"));
        var background=_light?new LinearGradientBrush(Color.FromArgb(245,245,248,250),Color.FromArgb(230,228,240,250),0):new LinearGradientBrush(Color.FromArgb(235,9,17,33),Color.FromArgb(184,14,28,54),0);
        dc.DrawGeometry(background,new Pen(Paint(_light?"#BAC9D1":"#47607B"),1),panel);
        dc.PushClip(panel);dc.DrawEllipse(new RadialGradientBrush(Color.FromArgb(50,86,146,236),Colors.Transparent),null,new(31,31),36,36);dc.Pop();
        var text=Timeline.Sample(".c-text",_time);dc.PushOpacity(Math.Clamp(text.Opacity,0,1));dc.PushTransform(new TranslateTransform(text.X,text.Y));
        dc.DrawText(_brand,new(66,12));var x=66d;dc.DrawText(_prefix,new(x,33));x+=_prefix.WidthIncludingTrailingWhitespace+2;var keyWidth=_binding.Width+8;
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(35,120,170,240)),new Pen(Paint(_light?"#799BB3":"#779CCB"),1),new(x,33,keyWidth,17),4,4);
        dc.DrawText(_binding,new(x+4,33));x+=keyWidth+2;dc.DrawText(_suffix,new(x,33));dc.Pop();dc.Pop();dc.Pop();
    }
    private void DrawScan(DrawingContext dc)
    {
        var state=Timeline.Sample(".c-edge",_time);if(state.Opacity<=0)return;var x=state.X*((VisibleWidth+OffscreenRight-2)/274d);
        dc.PushOpacity(Math.Clamp(state.Opacity,0,1));
        dc.DrawRoundedRectangle(new LinearGradientBrush(new GradientStopCollection{new(Colors.Transparent,0),new(Color.FromArgb(60,130,190,255),.5),new(Colors.Transparent,1)},90),null,new(x-8,4,18,54),8,8);
        dc.DrawRectangle(FlashBrush(90),null,new(x,6,2,50));dc.Pop();
    }
    private void DrawTrail(DrawingContext dc,string selector,string polygon,double x,double y,double width,double angle)
    {
        var state=Timeline.Sample(selector,_time);if(state.Opacity<=0)return;Push(dc,state,new(0,0),new(28,28));
        var clip=new StreamGeometry();using(var writer=clip.Open()){var points=polygon.Split(' ').Select(p=>p.Split(',')).Select(p=>new Point(double.Parse(p[0],CultureInfo.InvariantCulture)*56/1280,double.Parse(p[1],CultureInfo.InvariantCulture)*56/1280)).ToArray();writer.BeginFigure(points[0],true,true);writer.PolyLineTo(points.Skip(1).ToArray(),true,false);}
        dc.PushClip(clip);DrawBrandImage(dc,_mark);dc.Pop();
        var tail=Timeline.Sample(".c-tail-"+selector[3..],_time);
        if(tail.Opacity>0){dc.PushOpacity(Math.Clamp(tail.Opacity,0,1));dc.PushTransform(new TranslateTransform(x,y));dc.PushTransform(new RotateTransform(angle,width,.75));dc.DrawRoundedRectangle(TailBrush(),null,new(0,0,width,1.5),.75,.75);dc.Pop();dc.Pop();dc.Pop();}Pop(dc);
    }
    private static void Push(DrawingContext dc,MeteorState state,Point origin,Point center){dc.PushOpacity(Math.Clamp(state.Opacity,0,1));dc.PushTransform(new TranslateTransform(origin.X+state.X,origin.Y+state.Y));dc.PushTransform(new RotateTransform(state.Angle,center.X,center.Y));dc.PushTransform(new ScaleTransform(state.Scale,state.Scale,center.X,center.Y));}
    private static void Pop(DrawingContext dc){dc.Pop();dc.Pop();dc.Pop();dc.Pop();}
    private void DrawBrandImage(DrawingContext dc,BitmapSource image) {
        if (!_light) { dc.DrawImage(image,new(0,0,56,56)); return; }
        dc.PushOpacityMask(new ImageBrush(image)); dc.DrawRectangle(Paint("#24476C"),null,new(0,0,56,56)); dc.Pop();
    }
    private Brush TailBrush()=>new LinearGradientBrush(Colors.Transparent,_light?Color.FromRgb(65,115,170):Colors.White,0);
    private Brush FlashBrush(double angle)=>new LinearGradientBrush(new GradientStopCollection{new(Colors.Transparent,0),new(_light?Color.FromRgb(60,110,160):Colors.White,.5),new(Colors.Transparent,1)},angle);
    private static Brush Paint(string value)=>new SolidColorBrush((Color)ColorConverter.ConvertFromString(value));
    private FormattedText Text(string value,double size,Brush brush,bool bold=false,string font="Segoe UI")=>new(value,CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface(new FontFamily(font),FontStyles.Normal,bold?FontWeights.SemiBold:FontWeights.Normal,FontStretches.Normal),size,brush,VisualTreeHelper.GetDpi(this).PixelsPerDip);
    private static BitmapSource Image(string name){var assembly=Uri.EscapeDataString(typeof(GameStartupHintCard).Assembly.GetName().Name!);var bitmap=new BitmapImage(new Uri($"pack://application:,,,/{assembly};component/Assets/Brand/{name}.png"));bitmap.Freeze();return bitmap;}
}

internal readonly record struct MeteorState(double Opacity,double X,double Y,double Scale,double Angle,double Left,double Right,double Glow);
/// <summary>Samples the approved 17 tracks with CSS cubic-bezier timing, including overshoot.</summary>
internal sealed class MeteorTimeline
{
    private sealed record Frame(double At,MeteorState State,double[]? Ease);
    private readonly Dictionary<string,Frame[]> _tracks=[];
    private static readonly Regex Numbers=new(@"[-+]?(?:\d*\.)?\d+",RegexOptions.CultureInvariant);
    internal int TrackCount=>_tracks.Count;
    internal MeteorTimeline()
    {
        using var stream=typeof(MeteorTimeline).Assembly.GetManifestResourceStream("StarBridge.GameStartupMotion.json")??throw new InvalidOperationException("Startup motion resource missing.");using var json=JsonDocument.Parse(stream);
        foreach(var track in json.RootElement.EnumerateArray()){
            var frames=track.GetProperty("keyframes").EnumerateArray().Select(frame=>{
                string Value(string name)=>frame.TryGetProperty(name,out var value)?value.ToString():"";
                static double[] Args(string value,string name){var match=Regex.Match(value,Regex.Escape(name)+@"\(([^)]*)\)");return match.Success?Numbers.Matches(match.Groups[1].Value).Select(m=>double.Parse(m.Value,CultureInfo.InvariantCulture)).ToArray():[];}
                var transform=Value("transform");var xy=Args(transform,"translate");var tx=Args(transform,"translateX");var ty=Args(transform,"translateY");var scale=Args(transform,"scale");var angle=Args(transform,"rotate");var clip=Args(Value("clipPath"),"inset");var glow=Args(Value("filter"),"drop-shadow");var ease=Args(Value("easing"),"cubic-bezier");
                return new Frame(frame.GetProperty("at").GetDouble(),new(frame.TryGetProperty("opacity",out var op)?op.GetDouble():1,xy.Length>0?xy[0]:tx.FirstOrDefault(),xy.Length>1?xy[1]:ty.FirstOrDefault(),scale.Length>0?scale[0]:1,angle.FirstOrDefault(),clip.Length>3?clip[3]/100:0,clip.Length>1?clip[1]/100:0,glow.Length>2?glow[2]:0),ease.Length==4?ease:null);
            }).ToArray();
            if(frames.Length<2||frames[0].At!=0||frames[^1].At!=GameStartupHintCard.Total||frames.Zip(frames.Skip(1)).Any(p=>p.First.At>=p.Second.At))throw new InvalidOperationException("Invalid startup timeline.");
            _tracks.Add(track.GetProperty("selector").GetString()!,frames);
        }
    }
    internal MeteorState Sample(string selector,double time)
    {
        var frames=_tracks[selector];if(time<=0)return frames[0].State;if(time>=frames[^1].At)return frames[^1].State;
        var end=Array.FindIndex(frames,f=>f.At>time);var a=frames[end-1];var b=frames[end];var p=(time-a.At)/(b.At-a.At);if(a.Ease is {} ease)p=Bezier(p,ease);
        double L(double x,double y)=>x+(y-x)*p;
        return new(L(a.State.Opacity,b.State.Opacity),L(a.State.X,b.State.X),L(a.State.Y,b.State.Y),L(a.State.Scale,b.State.Scale),L(a.State.Angle,b.State.Angle),L(a.State.Left,b.State.Left),L(a.State.Right,b.State.Right),L(a.State.Glow,b.State.Glow));
    }
    private static double Bezier(double x,double[] c){if(x<=0)return 0;if(x>=1)return 1;static double Curve(double t,double a,double b)=>3*(1-t)*(1-t)*t*a+3*(1-t)*t*t*b+t*t*t;double low=0,high=1;for(var i=0;i<24;i++){var mid=(low+high)/2;if(Curve(mid,c[0],c[2])<x)low=mid;else high=mid;}return Curve((low+high)/2,c[1],c[3]);}
}

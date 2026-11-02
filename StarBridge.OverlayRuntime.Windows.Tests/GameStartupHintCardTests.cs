using StarBridge.HostRuntime.Notifications;
using StarBridge.Desktop;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.IO;
using System.Windows.Threading;

internal static class GameStartupHintCardTests
{
    internal static void Run()
    {
        var checks=0;Exception? failure=null;
        var thread=new Thread(()=>{
            try {
                void Check(bool value,string why){checks++;if(!value)throw new Exception(why);}
                var timeline=GameStartupHintCard.Timeline;
                Check(timeline.TrackCount==17,"All approved meteor layers retained");
                foreach(var selector in new[]{".c-m1",".c-m2",".c-m3",".c-m4",".c-ne",".c-nw",".c-se",".c-sw",".c-star"}){
                    var entry=timeline.Sample(selector,0);
                    Check(entry.X>0&&entry.Y<0,"Every incoming meteor starts above and right of its resting position");
                }
                var arrivingStar=timeline.Sample(".c-star",1030);
                Check(arrivingStar.X>0&&arrivingStar.Y<0&&arrivingStar.Scale>=.95&&arrivingStar.Angle==0,"Star arrives from upper right without tiny spinning ignition");
                Check(timeline.Sample(".c-star",1280).X==0&&timeline.Sample(".c-star",1280).Y==0,"Star settles into the original brand alignment");
                Check(timeline.Sample(".c-star",960).Opacity==0&&timeline.Sample(".c-star",1100).Opacity==1,"Main line precedes star ignition");
                Check(timeline.Sample(".c-ne",640).Opacity==0&&timeline.Sample(".c-ne",1000).Opacity==1,"Main meteor lands before information expands");
                for(var delta=0;delta<=500;delta+=25){
                    var opening=timeline.Sample(".c-card",1600+delta);var closing=timeline.Sample(".c-card",7500+delta);
                    Check(Math.Abs((1-opening.Right)-closing.Left)<.000001,"Matched opening/closing timing across the complete sweep");
                }
                var scan=timeline.Sample(".c-edge",2100);
                Check(scan.X==274&&scan.Opacity>.8,"Scan travels beyond the visible 260px edge before fading");
                Check(timeline.Sample(".c-card",8000).Left==1&&timeline.Sample(".c-star",8000).Opacity==0,"Complete exit leaves no static logo or card");
                foreach(var locale in new[]{"zh-CN","zh-TW","en-US"})
                foreach(var appearance in new[]{"dark","light"})
                foreach(var key in new[]{"Alt+M","Ctrl+Shift+Alt+M"}){
                    var card=new GameStartupHintCard(new(Guid.NewGuid(),false,0,0,"fullContent","topRight",locale,appearance,()=>true,GameStartupHint:new(key,42)));
                    Check(card.Height==190&&card.VisibleWidth>=260&&!card.IsHitTestVisible&&!card.Focusable,"Compact visible card and click-through travel canvas");
                    Check(card.Binding==key&&System.Windows.Automation.AutomationProperties.GetName(card).Contains(key),"Real custom shortcut remains complete and accessible");
                    Check(RenderOptions.GetBitmapScalingMode(card)==BitmapScalingMode.HighQuality,"Downscaled brand artwork uses high quality sampling");
                    foreach(var dpi in new uint[]{96,144,192}){
                        var game=new System.Drawing.Rectangle(-1920,80,1920,1080);var placement=GameStartupHintCard.Placement(game,dpi,card.VisibleWidth);var scale=dpi/96d;
                        Check(placement.Right==game.Right+(int)Math.Ceiling(16*scale),"Offscreen right extension scales on a negative-origin monitor");
                        Check(placement.Top+(int)Math.Round(64*scale)==game.Top+(int)Math.Round(160*scale),"Reserve 160DIP above the visible card for driver prompts");
                    }
                    var done=0;card.BeginPresentation(true,()=>done++);Check(card.PlaybackActive&&card.PlaybackTime==0,"Animated presentation starts at the first meteor");
                    card.Stop();Check(!card.PlaybackActive&&done==0,"Cancellation stops the clock without stale completion");
                    card.BeginPresentation(false,()=>done++);Check(card.PlaybackTime==2200&&card.PlaybackActive,"Reduced motion displays readable information immediately");card.Stop();
                    var output=Environment.GetEnvironmentVariable("STARBRIDGE_STARTUP_HINT_RENDER_OUTPUT");
                    if(!string.IsNullOrEmpty(output)){
                        Directory.CreateDirectory(output);
                        foreach(var time in new[]{0,800,1030,1100,1280,1850,2200,6780,7750,8000}){
                            card.SeekForTest(time);card.Measure(new(card.Width,card.Height));card.Arrange(new(0,0,card.Width,card.Height));card.UpdateLayout();
                            var bitmap=new RenderTargetBitmap((int)Math.Ceiling(card.Width*2),380,192,192,PixelFormats.Pbgra32);bitmap.Render(card);
                            var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using var file=File.Create(Path.Combine(output,$"startup-{locale}-{appearance}-{key.Replace('+','_')}-{time}.png"));png.Save(file);
                        }
                    }
                }
                var small=GameStartupHintCard.Placement(new(100,120,640,240),192,260);
                Check(small.Top+128>=120&&small.Top+128+124<=360,"Visible panel fits a small game client");
                var playback=new GameStartupHintCard(new(Guid.NewGuid(),false,0,0,"fullContent","topRight","zh-CN","dark",()=>true,GameStartupHint:new("Alt+M",42)));
                var completed=0;playback.BeginPresentation(true,()=>completed++);Pump(2350);
                Check(playback.PlaybackActive&&playback.PlaybackTime>=2200&&playback.PlaybackTime<2400&&completed==0,"Reading phase starts after meteor entry and survives the old 4.5s card deadline");
                Pump(5950);Check(!playback.PlaybackActive&&playback.PlaybackTime==8000&&completed==1,"Native clock completes exit once and stops");
                playback.BeginPresentation(false,()=>completed++);Pump(4650);
                Check(!playback.PlaybackActive&&completed==2,"Reduced motion retains only the 4.5s readable dwell, with no animated wait");
                playback.BeginPresentation(true,()=>completed++);playback.Stop();Pump(100);
                Check(!playback.PlaybackActive&&completed==2,"Revoked playback does not invoke a stale completion");
            }catch(Exception error){failure=error;}
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();thread.Join();if(failure!=null)throw failure;
        Console.WriteLine($"PASS game startup meteor card: {checks} checks; choreography, three locales, long bindings, themes, DPI placement, reduced motion and cancellation");
    }
    private static void Pump(int milliseconds){var frame=new DispatcherFrame();var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(milliseconds)};timer.Tick+=(_,_)=>{timer.Stop();frame.Continue=false;};timer.Start();Dispatcher.PushFrame(frame);}
}

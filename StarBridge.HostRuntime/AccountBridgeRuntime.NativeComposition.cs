using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Support;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    // The same Native consumer composition serves ordinary startup and the
    // original typed installation. It grants no authentication or mode rights.
    // Factories are entered only under that owner's actual configuration lease;
    // device sinks/export picker are borrowed, account observers/pickers owned.
    internal sealed class NativeBusinessComposition
    {
        private readonly string _dataRoot;
        private readonly Func<ICommunityLogoPicker> _images;
        private readonly IGameplayExportPicker _export;
        private readonly Func<AccountBridgeRuntime, PlayerActivityRuntime> _activity;
        private readonly IInformationOverlayLiveUpdateSink? _overlay;
        private readonly ISharedActivitySink? _shared;
        private readonly IAchievementCelebrationSink _celebration;
        private readonly NotificationSettingsBridgeDispatcher _notifications;
        private readonly NotificationAudioBridgeDispatcher _audio;

        internal NativeBusinessComposition(string dataRoot, Func<ICommunityLogoPicker> images,
            IGameplayExportPicker export, Func<AccountBridgeRuntime, PlayerActivityRuntime> activity,
            IInformationOverlayLiveUpdateSink? overlay, ISharedActivitySink? shared,
            IAchievementCelebrationSink celebration, NotificationSettingsBridgeDispatcher notifications,
            NotificationAudioBridgeDispatcher audio)
        {
            _dataRoot = dataRoot; _images = images; _export = export; _activity = activity;
            _overlay = overlay; _shared = shared; _celebration = celebration;
            _notifications = notifications; _audio = audio;
            Configure = ConfigureCore; // Stable identity for the one physical installation.
        }

        internal Action<AccountBridgeRuntime> Configure { get; }

        private void ConfigureCore(AccountBridgeRuntime owner)
        {
            using var work = owner.EnterAccountBusinessConfiguration();
            if (work is null || owner._host is not Account.ScmAccountBridgeHost)
                throw new InvalidOperationException("Native account configuration is unavailable.");
            void Current()
            {
                if (!work.IsCurrent || owner._disposed || owner._localBusinessRetired)
                    throw new OperationCanceledException("Original Native configuration retired.");
            }
            Current(); InstallImage(owner.ConfigureCommunityLogoPicker);
            Current(); InstallImage(owner.ConfigureHangarImagePicker);
            Current(); InstallImage(owner.ConfigureAchievementIdeaImagePicker);
            Current(); owner.ConfigureGameplayExportPicker(_export, _dataRoot);
            Current(); owner.ConfigureOverlayCommunitySource(_dataRoot);
            Current(); if (_overlay is not null) owner.ConfigureLiveOverlayUpdates(_overlay);
            Current(); if (_shared is not null) owner.ConfigureSharedActivity(_shared);
            Current();
            var activity = _activity(owner);
            try
            {
                Current();
                if (!owner.ConfigurePlayerActivityCore(activity, ownsRuntime: true))
                    throw new InvalidOperationException("Player activity observer is unavailable.");
            }
            catch { activity.Dispose(); throw; }
            Current(); owner.ConfigureTradeNotifications(_notifications);
            Current(); owner.ConfigureAchievementCelebration(_celebration);
            Current();
            if (!owner.ConfigureCommunityNotifications(_notifications, _audio))
                throw new InvalidOperationException("Community notification observer is unavailable.");
            Current();

            void InstallImage(Action<ICommunityLogoPicker> attach)
            {
                var picker = _images();
                try { Current(); attach(picker); }
                catch { picker.Dispose(); throw; }
            }
        }
    }
}

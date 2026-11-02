using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private NotificationSettingsBridgeDispatcher? _tradeNotifications;
    private readonly AsyncWorkRetirement _tradeNotificationWork = new();

    internal void ConfigureTradeNotifications(NotificationSettingsBridgeDispatcher notifications)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null || _host is not ScmAccountBridgeHost scm) return;
        if (_tradeNotifications is not null) throw new InvalidOperationException("Trade notifications already configured.");
        _tradeNotifications = notifications;
        scm.MarketplaceNoticePushed += PresentTradeNotice;
        scm.MarketplaceChatPushed += PresentTradeChat;
        _host.AccountChanged += InvalidateTradeNotifications;
    }

    private void PresentTradeNotice(BridgeAccountContext owner, long generation, TradeNotificationEvent notice)
        => _ = DeliverTradeNoticeAsync(owner, generation, notice);

    private void PresentTradeChat(long generation, object push)
    {
        if (_disposed || _localBusinessRetired || generation != Generation || _host.CurrentContext is not {} owner) return;
        var item = TradeNotificationEvent.ChatPush(JsonSerializer.SerializeToElement(push));
        if (item is not null) PresentTradeNotice(owner, generation, item);
    }

    private async Task DeliverTradeNoticeAsync(BridgeAccountContext owner, long generation, TradeNotificationEvent notice)
    {
        using var work = _tradeNotificationWork.Enter(default);
        if (work is null || _tradeNotifications is null) return;
        bool Current() => !_disposed && !_localBusinessRetired && generation == Generation && GameplayOwner().Context == owner &&
            _host is ScmAccountBridgeHost scm && scm.AllowsTradeNotification(notice.Chat) && scm.IsTradeNoticeUnread(notice);
        if (Current()) await _tradeNotifications.PresentTradeAsync(owner, generation, notice, Current, work.Token).ConfigureAwait(false);
    }

    private void InvalidateTradeNotifications(long _) => _tradeNotifications?.InvalidateTrade();
    private Task RetireTradeNotificationsAsync()
    {
        var retired = _tradeNotificationWork.Close();
        _tradeNotifications?.InvalidateTrade();
        return retired;
    }
    private void DisposeTradeNotifications()
    {
        if (_host is ScmAccountBridgeHost scm) {
            scm.MarketplaceNoticePushed -= PresentTradeNotice;
            scm.MarketplaceChatPushed -= PresentTradeChat;
        }
        _host.AccountChanged -= InvalidateTradeNotifications;
        _ = RetireTradeNotificationsAsync();
    }
}

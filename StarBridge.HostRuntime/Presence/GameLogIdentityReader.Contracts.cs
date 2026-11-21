using static StarBridge.HostRuntime.Presence.ContractNotificationLines;

namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameLogIdentityReader
{
    private bool ObserveContractNotification(string line, GameProcessSession? process, DateTimeOffset now)
    {
        try
        {
            if (_contractNotification is not null)
            {
                if (!TryContractContinuation(_contractNotification, line, out var body))
                { _contractNotification = null; InterruptContracts(); }
                else
                {
                    _contractNotification += " " + body;
                    if (_contractNotification.Length > MaximumLength)
                    { _contractNotification = null; InterruptContracts(); return true; }
                    if (CompleteContractNotification(_contractNotification))
                    {
                        var combined = _contractNotification; _contractNotification = null;
                        Observe(combined, process, now, _contractNotificationLive);
                    }
                    return true;
                }
            }
            if (IsIncompleteContractNotification(line))
            {
                _contractNotification = line;
                _contractNotificationLive = process is not null && _following && _lineStart >= _liveFrom;
                return true;
            }
            return false;
        }
        catch (Exception error)
        {
            var pending = _contractNotification;
            _contractNotification = null;
            _session?.ReportContractFault(error, pending ?? line);
            if (pending is not null) _session?.ReportContractFault(error, line);
            return true;
        }
    }

}

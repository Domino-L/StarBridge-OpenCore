using StarBridge.Core.Events;
using StarBridge.Core.Locations;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

internal enum LocationDataContributionConsentState
{
    Unknown,
    Allowed,
    Declined
}

internal sealed record LocationDataContributionConsent(
    int Version = LocationDataContributionRecorder.CurrentConsentVersion,
    LocationDataContributionConsentState State = LocationDataContributionConsentState.Unknown,
    DateTimeOffset UpdatedAt = default);

internal sealed record PendingLocationTarget(
    string Code,
    DateTimeOffset SelectedAt,
    DateTimeOffset? ArrivedAt = null);

internal sealed record LocationDataContributionState(
    LocationDataContributionConsent Consent,
    LocationCodeObservationContract[] PendingCodes,
    LocationPairObservationContract[] PendingPairs,
    string[] SubmittedKeys);

internal sealed class LocationDataContributionRecorder
{
    public const int CurrentConsentVersion = 1;
    private static readonly TimeSpan MaximumTargetAge = TimeSpan.FromMinutes(30);
    private static readonly TimeSpan MaximumArrivalConfirmationDelay = TimeSpan.FromMinutes(5);
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static readonly Regex BracketInstanceSuffixRegex = new(
        @"\s*\[\d+\]\s*$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private readonly string _path;
    private readonly Dictionary<string, LocationCodeObservationContract> _pendingCodes =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, LocationPairObservationContract> _pendingPairs =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _submittedKeys = new(StringComparer.OrdinalIgnoreCase);
    private PendingLocationTarget? _target;

    public LocationDataContributionRecorder(string? baseDirectory = null)
    {
        var root = string.IsNullOrWhiteSpace(baseDirectory)
            ? DesktopAppConfig.ConfigDirectory
            : baseDirectory;
        _path = Path.Combine(root, "LocationData", "contributions.json");
        Load();
    }

    public LocationDataContributionConsent Consent { get; private set; } = new();

    public bool IsAllowed =>
        Consent.Version >= CurrentConsentVersion &&
        Consent.State == LocationDataContributionConsentState.Allowed;

    public int PendingCount => _pendingCodes.Count + _pendingPairs.Count;

    public int SubmittedCount => _submittedKeys.Count;

    public string? LastWriteError { get; private set; }

    public void SetConsent(LocationDataContributionConsentState state, DateTimeOffset now)
    {
        if (!Enum.IsDefined(state))
        {
            state = LocationDataContributionConsentState.Unknown;
        }

        Consent = new LocationDataContributionConsent(CurrentConsentVersion, state, now);
        if (state != LocationDataContributionConsentState.Allowed)
        {
            _pendingCodes.Clear();
            _pendingPairs.Clear();
            _target = null;
        }

        Save();
    }

    public bool Observe(FleetEvent fleetEvent, DateTimeOffset observedAt)
    {
        if (!IsAllowed)
        {
            return false;
        }

        var eventAt = ResolveLogTimestamp(fleetEvent.SourceLine) ?? observedAt;
        var changed = fleetEvent.Type switch
        {
            FleetEventType.PlayerNavigationTargetChanged => ObserveNavigation(fleetEvent, eventAt),
            FleetEventType.PlayerLocationChanged => ObserveLocation(fleetEvent, eventAt),
            _ => false
        };

        if (changed)
        {
            Save();
        }

        return changed;
    }

    public LocationDataContributionRequestContract? CreateBatch(string clientId, int maximumItems = 100)
    {
        if (!IsAllowed || string.IsNullOrWhiteSpace(clientId) || maximumItems <= 0 || PendingCount == 0)
        {
            return null;
        }

        var codes = _pendingCodes.Values
            .OrderBy(value => value.Code, StringComparer.OrdinalIgnoreCase)
            .ThenBy(value => value.Source)
            .Take(maximumItems)
            .ToArray();
        var remaining = Math.Max(0, maximumItems - codes.Length);
        var pairs = _pendingPairs.Values
            .OrderBy(value => value.QuantumTargetCode, StringComparer.OrdinalIgnoreCase)
            .ThenBy(value => value.ActualLocationCode, StringComparer.OrdinalIgnoreCase)
            .Take(remaining)
            .ToArray();
        return new LocationDataContributionRequestContract(clientId.Trim(), codes, pairs);
    }

    public void Acknowledge(LocationDataContributionRequestContract batch)
    {
        foreach (var code in batch.Codes)
        {
            var key = CodeKey(code.Code, code.Source);
            _pendingCodes.Remove(key);
            _submittedKeys.Add(key);
        }

        foreach (var pair in batch.Pairs)
        {
            var key = PairKey(pair.QuantumTargetCode, pair.ActualLocationCode);
            _pendingPairs.Remove(key);
            _submittedKeys.Add(key);
        }

        Save();
    }

    public void ClearLocalObservations()
    {
        _pendingCodes.Clear();
        _pendingPairs.Clear();
        _submittedKeys.Clear();
        _target = null;
        Save();
    }

    private bool ObserveNavigation(FleetEvent fleetEvent, DateTimeOffset eventAt)
    {
        var changed = false;
        var targetCode = NormalizeCode(fleetEvent.NavigationTarget);
        if (targetCode is not null)
        {
            changed |= AddCode(targetCode, LocationCodeSourceContract.NavigationTarget);
            _target = new PendingLocationTarget(targetCode, eventAt);
        }

        var routeStart = NormalizeCode(fleetEvent.Location);
        if (routeStart is not null)
        {
            changed |= AddCode(routeStart, LocationCodeSourceContract.RouteStart);
        }

        return changed;
    }

    private bool ObserveLocation(FleetEvent fleetEvent, DateTimeOffset eventAt)
    {
        if (IsQuantumArrival(fleetEvent.Location))
        {
            if (_target is not null &&
                eventAt >= _target.SelectedAt &&
                eventAt - _target.SelectedAt <= MaximumTargetAge)
            {
                _target = _target with { ArrivedAt = eventAt };
            }

            return false;
        }

        if (!string.Equals(
                fleetEvent.LocationEvidence,
                "Location inventory context",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var actualCode = NormalizeCode(fleetEvent.Location);
        if (actualCode is null)
        {
            return false;
        }

        var changed = AddCode(actualCode, LocationCodeSourceContract.InventoryLocation);
        if (_target?.ArrivedAt is not { } arrivedAt || eventAt < arrivedAt)
        {
            return changed;
        }

        var delay = eventAt - arrivedAt;
        if (delay > MaximumArrivalConfirmationDelay)
        {
            _target = null;
            return changed;
        }

        var pair = new LocationPairObservationContract(
            _target.Code,
            actualCode,
            Math.Clamp((int)Math.Round(delay.TotalSeconds), 0, (int)MaximumArrivalConfirmationDelay.TotalSeconds));
        var pairKey = PairKey(pair.QuantumTargetCode, pair.ActualLocationCode);
        if (!_submittedKeys.Contains(pairKey) && !_pendingPairs.ContainsKey(pairKey))
        {
            _pendingPairs[pairKey] = pair;
            changed = true;
        }

        _target = null;
        return changed;
    }

    private bool AddCode(string code, LocationCodeSourceContract source)
    {
        var observation = new LocationCodeObservationContract(code, source);
        var key = CodeKey(code, source);
        if (_submittedKeys.Contains(key) || _pendingCodes.ContainsKey(key))
        {
            return false;
        }

        _pendingCodes[key] = observation;
        return true;
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_path))
            {
                return;
            }

            var state = JsonSerializer.Deserialize<LocationDataContributionState>(File.ReadAllText(_path));
            if (state is null)
            {
                return;
            }

            Consent = state.Consent is { } consent && Enum.IsDefined(consent.State)
                ? consent
                : new LocationDataContributionConsent();
            foreach (var observation in state.PendingCodes ?? [])
            {
                var code = NormalizeCode(observation.Code);
                if (code is not null && Enum.IsDefined(observation.Source))
                {
                    _pendingCodes[CodeKey(code, observation.Source)] = observation with { Code = code };
                }
            }

            foreach (var pair in state.PendingPairs ?? [])
            {
                var target = NormalizeCode(pair.QuantumTargetCode);
                var actual = NormalizeCode(pair.ActualLocationCode);
                if (target is not null && actual is not null)
                {
                    _pendingPairs[PairKey(target, actual)] = pair with
                    {
                        QuantumTargetCode = target,
                        ActualLocationCode = actual,
                        ArrivalToConfirmationSeconds = Math.Clamp(pair.ArrivalToConfirmationSeconds, 0, 300)
                    };
                }
            }

            foreach (var key in state.SubmittedKeys ?? [])
            {
                if (!string.IsNullOrWhiteSpace(key))
                {
                    _submittedKeys.Add(key.Trim());
                }
            }
        }
        catch
        {
            Consent = new LocationDataContributionConsent();
            _pendingCodes.Clear();
            _pendingPairs.Clear();
            _submittedKeys.Clear();
        }
    }

    private void Save()
    {
        try
        {
            var directory = Path.GetDirectoryName(_path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var state = new LocationDataContributionState(
                Consent,
                _pendingCodes.Values.ToArray(),
                _pendingPairs.Values.ToArray(),
                _submittedKeys.OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray());
            File.WriteAllText(_path, JsonSerializer.Serialize(state, JsonOptions));
            LastWriteError = null;
        }
        catch (Exception ex)
        {
            LastWriteError = UserFacingError.Describe(ex, "地点数据未能保存，请稍后重试。");
            throw;
        }
    }

    private static string? NormalizeCode(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
            value.Equals("None", StringComparison.OrdinalIgnoreCase) ||
            IsQuantumArrival(value))
        {
            return null;
        }

        var normalized = BracketInstanceSuffixRegex.Replace(value.Trim(), "").Trim();
        if (normalized.Length is < 2 or > 128 ||
            normalized.Any(character => !(char.IsLetterOrDigit(character) || character is '_' or '-' or '.' or ':')))
        {
            return null;
        }

        return normalized;
    }

    private static bool IsQuantumArrival(string? value) =>
        !string.IsNullOrWhiteSpace(value) &&
        value.StartsWith("Arrived -", StringComparison.OrdinalIgnoreCase);

    private static string CodeKey(string code, LocationCodeSourceContract source) => $"code|{source}|{code}";

    private static string PairKey(string target, string actual) => $"pair|{target}|{actual}";

    private static DateTimeOffset? ResolveLogTimestamp(string? line)
    {
        if (string.IsNullOrWhiteSpace(line) || line[0] != '<')
        {
            return null;
        }

        var end = line.IndexOf('>');
        if (end <= 1 || end > 64)
        {
            return null;
        }

        return DateTimeOffset.TryParse(
            line[1..end],
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal,
            out var parsed)
            ? parsed
            : null;
    }
}

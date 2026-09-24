using System.Text.Json;

namespace StarBridge.HostRuntime.Support;

public interface IGameplayExportPicker
{
    Task<string?> ChooseNewJsonFileAsync(string suggestedName, string locale, CancellationToken cancellation);
}

internal sealed record GameplayExportData(
    int SchemaVersion, DateTimeOffset ExportedAtUtc, string RecordingConsent,
    long TotalSeconds, long SavedSeconds, long HistoricalSeconds,
    DateTimeOffset? HistoryImportedAt, bool ShowOnProfile)
{
    internal static GameplayExportData FromProjection(JsonElement body, DateTimeOffset exportedAt)
    {
        if (body.ValueKind != JsonValueKind.Object || body.GetProperty("schemaVersion").GetInt32() != 1 ||
            body.TryGetProperty("error", out var error) && error.ValueKind != JsonValueKind.Null)
            throw new GameplayExportException("gameplayExport.data_unavailable");
        var consent = body.GetProperty("consent").GetString();
        var total = body.GetProperty("seconds").GetInt64();
        var saved = body.GetProperty("savedSeconds").GetInt64();
        var historical = body.GetProperty("historicalSeconds").GetInt64();
        DateTimeOffset? history = body.TryGetProperty("historyImportedAt", out var historyValue) &&
            historyValue.ValueKind != JsonValueKind.Null ? historyValue.GetDateTimeOffset() : null;
        if (consent is not ("allowed" or "declined" or "unknown") || total < 0 || saved < 0 ||
            saved > total || historical < 0 || historical > saved || historical > 0 && history is null)
            throw new GameplayExportException("gameplayExport.data_unavailable");
        // Deliberately construct a whitelist. Never serialize a runtime/store object.
        return new(1, exportedAt, consent, total, saved, historical, history,
            body.GetProperty("showOnProfile").GetBoolean());
    }
}

internal sealed class GameplayExportException(string code) : Exception(code)
{
    internal string Code { get; } = code;
}

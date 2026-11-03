namespace StarBridge.HostRuntime.Privacy;

// Temporary, local-only diagnostic probe [DEBUG-community-read]. No payloads,
// exception messages, endpoints, account identifiers or credentials are accepted.
internal sealed class CommunityReadJournal(string root)
{
    private static readonly object Gate = new();
    internal void Record(string stage, string code, int? status, long elapsedMs) => RecordCore(stage, code, status, elapsedMs);
    internal void RecordReceipt(string stage, string code, int status, string contentType, long? bodyLength, string? mismatchField = null)
    {
        if (code == "ok") return;
        RecordCore(stage, code, status, 0, contentType, bodyLength, mismatchField);
    }

    private void RecordCore(string stage, string code, int? status, long elapsedMs, string? contentType = null, long? bodyLength = null,
        string? mismatchField = null)
    {
        if (stage is not ("bridge" or "relay" or "workspace-http" or "workspace-media-http" or "workspace-membership-http" or "workspace-snapshot-http" or "workspace-session-http" or "publication-gate" or "publication-identity" or "publication-send" or "publication-http" or "account-gate-event-read" or "account-gate-event-write" or "chat-read-receipt" or
            "official-ships-http" or "official-ships-host" or "official-members" or "official-runtime-members" or "official-hangar-entry" or "official-governance-activation" or
            "official-announcements" or "official-announcement-detail" or "official-announcement-editor" or
            "official-hangar-current-http" or "official-hangar-current-parse" or "official-hangar-intents-http" or
            "official-hangar-intents-parse" or "official-hangar-project" or "official-hangar-shape" or "publication-receipt" or
            "publication-membership" or "publication-community-directory" or "publication-member-directory" or "publication-official-context" or
            "publication-official-consent-read" or "publication-official-consent-save" or "publication-official-consent-check")) return;
        var safeCode = code switch
        {
            "draft-invalid" or "draft-fields-invalid" or "schema-invalid" or "edit-ref-invalid" or "source-ref-invalid" or
            "state-invalid" or "strategy-invalid" or "inventory-state-invalid" or "maximum-selected-invalid" or "selected-count-invalid" or
            "selected-refs-invalid" or "selected-refs-duplicate" or "scopes-invalid" or "scope-ref-invalid" or "flags-invalid" or
            "image-features-invalid" or "image-count-invalid" or "clear-images-invalid" or "publish-without-complete" or "scope-missing" or
            "selected-count-mismatch" or "selection-unknown-with-refs" or "selected-without-pool" or "scope-row-invalid" or
            "scope-fields-invalid" or "scope-ref-duplicate" or "scope-name-invalid" or "scope-current-invalid" or "scope-not-found" or
            "page-invalid" or "page-fields-invalid" or "page-offset-invalid" or "page-total-invalid" or "options-invalid" or
            "options-too-many" or "page-count-mismatch" or "page-next-invalid" or "option-invalid" or "option-fields-invalid" or
            "ship-ref-invalid" or "ship-ref-duplicate" or "option-flags-invalid" or "blank-name" or "name-invalid" or
            "name-too-long" or "name-control-char" or "page-edit-mismatch" or "page-offset-not-zero" => code,
            "timeout" or "unavailable" or "transient" or "forbidden" or "reauthorization" or "data-invalid" or "host-unavailable" => code,
            "no-session" or "no-relay-session" or "reauthorization-required" or "credential-unavailable" or
                "communities-unavailable" or "stale-generation" or "relay-send-failed" or "reached-client" => code,
            "upgrade-required" or "not-sent" or "duplicate" or "invalid" or "identityUnavailable" or
                "notAllowed" or "conflict" or "storageLimitReached" or "operationOutcomeUnknown" or "outcomeUnknown" => code,
            "ok" or "cancelled" or "network" or "http-error" or "account.reauthorization_required" or "parse-failed" or "not-found" => code,
            "communities.dataInvalid" or "communities.refreshRequired" or "communities.unavailable" or "communities.identityUnavailable" => code,
            "ships-descriptor" or "ships-page" or "ships-lookups" or "ships-identity-read" or "ships-identity-compare" or "ships-binding" or
            "ships-project" or "ships-timeout" or "communities.notAllowed" or "communities.mediaChanged" => code,
            "accepted" or "reference-expired" or "body-too-large" or "cursor-mismatch" or "invalid-response" or "account-changed" => code,
            "scm_business_identity_unavailable" or "scm_identity_unavailable" or "legacy_account_missing" => code,
            "privacy_publication.account_changed" or "privacy_publication.identity_unavailable" or
            "privacy_publication.identity_required" or "privacy_publication.forbidden" or
            "privacy_publication.community_scopes_unavailable" or "privacy_publication.response_invalid" or
            "privacy_publication.invalid_request" or "privacy_publication.temporarily_unavailable" or
            "privacy_publication.unavailable" => code,
            _ => "unclassified"
        };
        try
        {
            lock (Gate)
            {
                var directory = Path.GetFullPath(root);
                for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                    if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
                var path = Path.Combine(directory, "community-read-diagnostics.log");
                var backup = path + ".1";
                if (IsReparsePoint(path) || IsReparsePoint(backup)) return;
                Directory.CreateDirectory(directory);
                var safeStatus = status is >= 100 and <= 599 ? status.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) : "none";
                var metadata = contentType is not null
                    ? $" contentType={(contentType is "json" or "html" or "text" or "other" or "none" ? contentType : "other")} bodyLength={(bodyLength is >= 0 ? bodyLength.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) : "none")}" : "";
                if (PrivacyRelayWriter.IsReceiptField(mismatchField)) metadata += $" mismatchField={mismatchField}";
                var line = $"{DateTimeOffset.UtcNow:O} [DEBUG-community-read] stage={stage} code={safeCode} status={safeStatus} elapsedMs={Math.Clamp(elapsedMs, 0, 3600000)}{metadata}{Environment.NewLine}";
                if (File.Exists(path) && new FileInfo(path).Length + System.Text.Encoding.UTF8.GetByteCount(line) > 128 * 1024)
                    File.Move(path, backup, overwrite: true);
                File.AppendAllText(path, line);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
    }

    private static bool IsReparsePoint(string path)
    {
        try { return File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }
}

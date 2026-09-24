namespace StarBridge.HostRuntime.Auth;

public enum IdentityLinkOutcome
{
    NoLegacyCredential,
    AlreadyLinked,
    Linked,
    Conflict,
    ExistingLinkMismatch
}

public sealed record IdentityLinkCoordinatorResult(
    IdentityLinkOutcome Outcome,
    string? LegacyAccountId = null,
    string? ConflictId = null);

public sealed class IdentityLinkCoordinator(
    IIdentityLinkAuthorizationClient authorizationClient,
    IIdentityLinkClient identityLinkClient,
    ILegacyMigrationCredentialStore credentialStore)
{
    public Task<ScmIdentityLinkProjection?> ResolveAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken) =>
        identityLinkClient.ResolveAsync(session, cancellationToken);

    public async Task<IdentityLinkCoordinatorResult> EnsureLinkedAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null,
        Func<CancellationToken, Task<LegacyIdentityLinkPasswordCredential?>>? requestPasswordCredential = null,
        bool useStoredCredential = true)
    {
        ArgumentNullException.ThrowIfNull(session);
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var credential = useStoredCredential ? credentialStore.Load() : null;
        ScmAuthDiagnostics.Write(
            correlationId,
            "identity-link-flow",
            "started",
            $"legacyCredentialPresent={credential is not null} passwordPromptAvailable={requestPasswordCredential is not null}");
        reportProgress?.Invoke("正在检查 SCM 账号是否已关联旧账号...");
        var existing = await identityLinkClient.ResolveAsync(session, cancellationToken);
        if (existing is not null)
        {
            ScmAuthDiagnostics.Write(correlationId, "identity-link-resolve", "linked");
            if (credential is null)
            {
                return new IdentityLinkCoordinatorResult(
                    IdentityLinkOutcome.AlreadyLinked,
                    existing.LegacyAccountId);
            }

            if (!SameAccount(existing.LegacyAccountId, credential.AccountId))
            {
                return new IdentityLinkCoordinatorResult(
                    IdentityLinkOutcome.ExistingLinkMismatch,
                    existing.LegacyAccountId);
            }

            credentialStore.Delete();
            return new IdentityLinkCoordinatorResult(
                IdentityLinkOutcome.AlreadyLinked,
                existing.LegacyAccountId);
        }

        if (credential is null && requestPasswordCredential is null)
        {
            return new IdentityLinkCoordinatorResult(IdentityLinkOutcome.NoLegacyCredential);
        }

        var linkSession = await authorizationClient.AuthorizeIdentityLinkAsync(
            session,
            cancellationToken,
            reportProgress);
        ScmAuthDiagnostics.Write(correlationId, "identity-link-authorize", "completed");
        reportProgress?.Invoke("SCM 授权成功，正在创建安全关联挑战...");
        var challenge = await identityLinkClient.CreateChallengeAsync(linkSession, cancellationToken);
        ScmAuthDiagnostics.Write(correlationId, "identity-link-challenge", "completed");
        SignedIdentityLinkProof proof;
        if (credential is not null)
        {
            try
            {
                proof = await identityLinkClient.RequestLegacyProofAsync(
                    challenge,
                    credential,
                    cancellationToken);
            }
            catch (System.Net.Http.HttpRequestException exception)
                when (exception.StatusCode == System.Net.HttpStatusCode.Unauthorized &&
                      requestPasswordCredential is not null)
            {
                ScmAuthDiagnostics.Write(correlationId, "identity-link-bearer-proof", "unauthorized");
                proof = await RequestPasswordProofAsync(
                    challenge,
                    requestPasswordCredential,
                    cancellationToken,
                    correlationId);
            }
        }
        else
        {
            reportProgress?.Invoke("关联挑战已就绪，请验证旧 StarBridge 账号...");
            proof = await RequestPasswordProofAsync(
                challenge,
                requestPasswordCredential!,
                cancellationToken,
                correlationId);
        }
            ScmAuthDiagnostics.Write(correlationId, "identity-link-proof", "completed");

        reportProgress?.Invoke("旧账号验证通过，正在提交 SCM 关联确认...");
        var result = await identityLinkClient.ConsumeProofAsync(
            linkSession,
            proof,
            cancellationToken);
            ScmAuthDiagnostics.Write(correlationId, "identity-link-consume", "completed");
        if (credential is not null && !SameAccount(result.LegacyAccountId, credential.AccountId))
        {
            throw new ScmApiProtocolException("SCM 返回的旧账号与本地迁移凭据不一致。");
        }

        if (string.Equals(result.Status, "CONFLICT", StringComparison.OrdinalIgnoreCase))
        {
            return new IdentityLinkCoordinatorResult(
                IdentityLinkOutcome.Conflict,
                result.LegacyAccountId,
                result.ConflictId);
        }

        if (!string.Equals(result.Status, "LINKED", StringComparison.OrdinalIgnoreCase))
        {
            throw new ScmApiProtocolException("SCM 返回了未知的旧账号关联状态。");
        }

        var expectedLegacyAccountId = credential?.AccountId ?? result.LegacyAccountId;
    reportProgress?.Invoke("SCM 已接受关联，正在完成最终复核...");
        var confirmed = await identityLinkClient.ResolveAsync(session, cancellationToken);
        if (confirmed is null ||
            !string.Equals(confirmed.Status, "ACTIVE", StringComparison.OrdinalIgnoreCase) ||
            !SameAccount(confirmed.LegacyAccountId, expectedLegacyAccountId))
        {
            throw new ScmApiProtocolException("SCM 未能复核刚完成的旧账号关联。");
        }

        if (useStoredCredential)
        {
            credentialStore.Delete();
        }
        return new IdentityLinkCoordinatorResult(
            IdentityLinkOutcome.Linked,
            confirmed.LegacyAccountId);
    }

    public async Task<IdentityLinkCoordinatorResult> ProvisionCompatibilityAccountAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken,
        Action<string>? reportProgress = null)
    {
        ArgumentNullException.ThrowIfNull(session);
        reportProgress?.Invoke("正在检查 SCM 账号兼容档案...");
        var existing = await identityLinkClient.ResolveAsync(session, cancellationToken);
        if (existing is not null)
        {
            return new IdentityLinkCoordinatorResult(
                IdentityLinkOutcome.AlreadyLinked,
                existing.LegacyAccountId);
        }

        var linkSession = await authorizationClient.AuthorizeIdentityLinkAsync(
            session,
            cancellationToken,
            reportProgress);
        var commandId = Guid.NewGuid().ToString();
        reportProgress?.Invoke("正在创建旧业务兼容档案...");
        var result = await identityLinkClient.ProvisionCompatibilityAccountAsync(
            linkSession,
            commandId,
            cancellationToken);
        if (string.Equals(result.Status, "CONFLICT", StringComparison.OrdinalIgnoreCase))
        {
            return new IdentityLinkCoordinatorResult(
                IdentityLinkOutcome.Conflict,
                result.LegacyAccountId,
                result.ConflictId);
        }
        if (!string.Equals(result.Status, "LINKED", StringComparison.OrdinalIgnoreCase))
        {
            throw new ScmApiProtocolException("SCM 返回了未知的兼容档案状态。");
        }

        reportProgress?.Invoke("兼容档案已创建，正在完成最终复核...");
        var confirmed = await identityLinkClient.ResolveAsync(session, cancellationToken);
        if (confirmed is null ||
            !string.Equals(confirmed.Status, "ACTIVE", StringComparison.OrdinalIgnoreCase) ||
            !SameAccount(confirmed.LegacyAccountId, result.LegacyAccountId))
        {
            throw new ScmApiProtocolException("SCM 未能复核刚创建的兼容档案。");
        }

        return new IdentityLinkCoordinatorResult(
            IdentityLinkOutcome.Linked,
            confirmed.LegacyAccountId);
    }

    private async Task<SignedIdentityLinkProof> RequestPasswordProofAsync(
        ScmIdentityLinkChallenge challenge,
        Func<CancellationToken, Task<LegacyIdentityLinkPasswordCredential?>> requestPasswordCredential,
        CancellationToken cancellationToken,
        string correlationId)
    {
        ScmAuthDiagnostics.Write(correlationId, "identity-link-password-prompt", "started");
        var passwordCredential = await requestPasswordCredential(cancellationToken);
        if (passwordCredential is null)
        {
            ScmAuthDiagnostics.Write(correlationId, "identity-link-password-prompt", "cancelled");
            throw new OperationCanceledException("旧账号密码验证已取消。", cancellationToken);
        }
        ScmAuthDiagnostics.Write(correlationId, "identity-link-password-prompt", "completed");

        return await identityLinkClient.RequestLegacyProofAsync(
            challenge,
            passwordCredential,
            cancellationToken);
    }

    private static bool SameAccount(string? first, string? second) =>
        !string.IsNullOrWhiteSpace(first) &&
        !string.IsNullOrWhiteSpace(second) &&
        first.Trim().Equals(second.Trim(), StringComparison.OrdinalIgnoreCase);
}

using StarBridge.HostRuntime.Auth;

internal static partial class LegacyPasswordLoginTests
{
    private sealed class ScmVisitorVault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("Read cannot save credentials");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }

    private sealed class ScmVisibilityAuthorization : IProfileWriteAuthorizationClient
    {
        internal int Calls;
        internal string Mode = "granted";
        public Task<ScmOAuthSession> AuthorizeProfileWriteAsync(
            ScmOAuthSession session, CancellationToken token, Action<string>? reportProgress = null)
        {
            Calls++;
            if (Mode == "denied") throw new ScmApiForbiddenException("synthetic");
            return Task.FromResult(session with { AccessToken = "synthetic-write-token",
                Subject = Mode == "wrong-subject" ? "other" : session.Subject,
                Capabilities = Mode == "missing-scope" ? [] : ["profile.write"] });
        }
    }
}

# StarBridge public client

Flutter owns UI/state; the local .NET Host owns Windows capabilities and local
persistence. NativeBridge is the client/Host contract. Hosted backend code,
production deployment, private credentials and commercial appearance
implementations do not belong here. The retired Desktop app is not a dependency.

Read README.md, CONTRIBUTING.md and ASSET_POLICY.md before editing. Run the
checks in scripts/Test StarBridge Public Client.ps1 for CI-equivalent validation.
Console .NET regression projects run with dotnet run, not dotnet test.

Keep restricted data, third-party media and commercial appearance flags false.
Missing optional media is expected. Preserve fail-closed authorization and user
privacy; do not introduce server-side fallbacks or test accounts into normal UX.

Do not commit generated Flutter caches, build outputs, screenshots, private logs,
account data, keys or tokens. Public assets must match client-assets.json and
their separate licenses. Forks or modified builds must replace proprietary branding.

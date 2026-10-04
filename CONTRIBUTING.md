# Contributing to StarBridge

Thank you for helping improve StarBridge Open Core.

## Scope

The public repository accepts changes to:

- the Flutter Windows client and its public user experience;
- local Windows Host capabilities and client-side remote adapters (not hosted backend implementations);
- fleet, party-room, friends, profile, hangar, and communication clients;
- the public overlay framework, layout editor, and built-in open appearances;
- read-only `Game.log` watching and parsing;
- ship, location, quantum-travel and presence inference;
- public state and collaboration contracts;
- regression tests and public algorithm documentation.

The hosted service, production deployment configuration, commercial
entitlement implementation, and the Night Shadow and Verdict appearance source
are maintained outside this repository. Stable appearance IDs and compatibility
contracts may remain public so settings can migrate safely.

## Before submitting a change

1. Do not include personal logs, account identifiers, tokens, private server
   addresses, game screenshots, commercial appearance source, or third-party
   assets. Follow `ASSET_POLICY.md` for every new image, icon, font, audio, or
   other media file.
2. Add or update a regression test when behavior changes.
3. Run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test Repository Safety.ps1"
   pwsh -NoProfile -File ".\scripts\Test StarBridge Public Client.ps1" -MenuOverlay
   ```

4. Keep changes focused and explain any assumptions about the game log format.

By submitting a contribution, you agree that your contribution may be
distributed under the Apache License 2.0 used by this repository.

Every commit must also carry a Developer Certificate of Origin sign-off:

```text
Signed-off-by: Contributor Name <email@example.com>
```

Create it with `git commit -s`. By adding the sign-off, you certify the
statements in the repository's `DCO` file. Use an email address you are
comfortable recording in the public Git history.

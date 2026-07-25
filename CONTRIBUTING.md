# Contributing to StarBridge Open Core

Thank you for helping improve StarBridge Open Core.

## Scope

The public repository currently accepts changes to:

- read-only `Game.log` watching and parsing;
- ship, location, quantum-travel and presence inference;
- public state and collaboration contracts;
- regression tests and public algorithm documentation.

The desktop product, hosted service, deployment configuration, commercial
entitlement implementation, and the Night Shadow and Verdict appearances are
maintained outside this repository.

## Before submitting a change

1. Do not include personal logs, account identifiers, tokens, private server
   addresses, game screenshots, or third-party assets.
2. Add or update a regression test when behavior changes.
3. Run:

   ```powershell
   dotnet build StarBridge.sln
   dotnet run --project StarBridge.Core.Tests/StarBridge.Core.Tests.csproj
   powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test Repository Safety.ps1"
   ```

4. Keep changes focused and explain any assumptions about the game log format.

By submitting a contribution, you agree that your contribution may be
distributed under the Apache License 2.0 used by this repository.

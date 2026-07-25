# StarBridge Open Core

StarBridge Open Core contains the read-only `Game.log` parsing and state
inference code used by StarBridge.

This source release currently includes:

- read-only `Game.log` watching and event parsing;
- ship, location, quantum-travel and presence inference;
- normalized collaboration contracts used by the core;
- executable regression tests for the public algorithms;
- the detailed log-listening algorithm guide.

The default in-game overlay foundation is intended to join this open core after
its renderer has been separated from the private desktop product. It is not
included in this first export. The Night Shadow and Verdict commercial
appearances are proprietary and are never included.

## Build

Requirements:

- .NET 8 SDK

Commands:

```powershell
dotnet build StarBridge.sln
dotnet run --project StarBridge.Core.Tests/StarBridge.Core.Tests.csproj
```

## Contributing and security

Contributions are welcome when they stay inside the published open-core scope.
See `CONTRIBUTING.md` before opening a pull request.

Please do not attach personal `Game.log` files, account data, tokens, private
server addresses or other sensitive material to a public issue. See
`SECURITY.md` for private security reporting guidance.

## License

The files in this exported repository are licensed under the Apache License
2.0 unless a file says otherwise. Product names, logos, commercial appearances,
and third-party game media are excluded; see `TRADEMARKS.md`.

This project is an independent community tool and is not affiliated with,
authorized by, or endorsed by Cloud Imperium Games or Roberts Space Industries.

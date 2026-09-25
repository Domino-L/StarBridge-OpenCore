# Historical cleanup inventory

`wpf-0.6.6.1-files.json` contains only public release-relative file names, sizes
and SHA-256 digests, not user installation paths or user data. It is embedded in
the maintenance helper; runtime callers cannot supply a replacement inventory.

Source: the official 0.6.6.1 update ZIP, SHA-256
`d5cd3aa24f0aedd2a20758ae0137bb4029c5f70617a9ce457b07b426aa0c8ef0`.
The previously released signed update manifest was verified with its shipped
cryptographic verifier. The corresponding complete installer has SHA-256
`0a748eee24f8383f16035204d1a5c21d425af37e5bfb2b43b8bd8dc1e72af55d`;
its Authenticode signature and timestamp were also valid during this audit.
These are immutable historical references, not instructions to trust future
files at the same URL or to execute a local uninstaller.

525 payload files are covered. The ZIP directory entry and diagnostic
`PAYLOAD-SHA256SUMS.txt` are excluded. Unknown installation files, generated
uninstall records and WebView/user state are deliberately not removed by this
module. No historical uninstaller is executed. The inventory does not authorize
retiring the Windows installation registration; the coordinator must establish
that identity and a healthy successor separately.

Reproduce against the exact original archive (read-only):

```powershell
& '.\scripts\Test StarBridge Wpf Cleanup Inventory.ps1' -ReleaseZip '<original-0.6.6.1-update.zip>'
```

Do not regenerate this policy by hashing a user's existing installation, accept
changed known files as trusted, or use this allowlist to recursively erase an
installation directory. Files are moved into recovery storage first; disposal
of recovery copies requires a separate verified retention/cleanup operation.

# Third-Party Notices

This file indexes the NuGet components restored for the StarBridge desktop
client. The complete license text for every listed package is stored in
`licenses/`.

The machine-readable inventory is `third-party-packages.json`. CI compares that
inventory with `StarBridge.Desktop/obj/project.assets.json` after restore and
fails when a packaged dependency is missing, has changed version, or lacks its
declared license file.

| Package | Version | License | License file |
| --- | --- | --- | --- |
| Microsoft.Web.WebView2 | 1.0.2592.51 | BSD-3-Clause-style package license | `licenses/Microsoft.Web.WebView2-1.0.2592.51.txt` |
| SharpGen.Runtime | 2.4.2-beta | MIT | `licenses/SharpGen.Runtime-2.4.2-beta.txt` |
| SharpGen.Runtime.COM | 2.4.2-beta | MIT | `licenses/SharpGen.Runtime.COM-2.4.2-beta.txt` |
| System.IO.Pipelines | 9.0.1 | MIT | `licenses/System.IO.Pipelines-9.0.1.txt` |
| System.Text.Encodings.Web | 9.0.1 | MIT | `licenses/System.Text.Encodings.Web-9.0.1.txt` |
| System.Text.Json | 9.0.1 | MIT | `licenses/System.Text.Json-9.0.1.txt` |
| Vortice.Direct2D1 | 3.8.3 | MIT | `licenses/Vortice.Direct2D1-3.8.3.txt` |
| Vortice.Direct3D11 | 3.8.3 | MIT | `licenses/Vortice.Direct3D11-3.8.3.txt` |
| Vortice.DirectComposition | 3.8.3 | MIT | `licenses/Vortice.DirectComposition-3.8.3.txt` |
| Vortice.DirectX | 3.8.3 | MIT | `licenses/Vortice.DirectX-3.8.3.txt` |
| Vortice.DXGI | 3.8.3 | MIT | `licenses/Vortice.DXGI-3.8.3.txt` |
| Vortice.Mathematics | 2.1.0 | MIT | `licenses/Vortice.Mathematics-2.1.0.txt` |

Microsoft.Web.WebView2 also ships an upstream third-party notice:
`licenses/Microsoft.Web.WebView2-1.0.2592.51-NOTICE.txt`.

Official self-contained Windows packages also include the .NET host license and
third-party notice copied from the .NET installation used to build that exact
binary. These generated files are named
`Microsoft.NET.Runtime-LICENSE.txt` and
`Microsoft.NET.Runtime-ThirdPartyNotices.txt` in the installed `licenses/`
directory.

Star Citizen, Squadron 42, Roberts Space Industries, Cloud Imperium, and related
names and marks belong to their respective owners. Game data and localization
boundaries are documented separately in `DATA_RIGHTS.md`; media boundaries are
documented in `ASSET_POLICY.md`.

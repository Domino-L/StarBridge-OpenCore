# 第三方媒体说明

StarBridge 的 Apache-2.0 开放源码包不包含舰船缩略图、舰船详情图和星系地图原图。
这些图片即使出现在 StarBridge 的内部工作区或官方客户端中，也不会因此自动采用
Apache-2.0。

官方客户端可以保留完整的图片体验，但只有满足以下条件的图片才可以进入公开发布的
安装包或更新包：

- 图片列入 `third-party-media-manifest.json`，且文件路径、大小和 SHA-256 完全一致；
- `third-party-media-sources.json` 中记录可追溯的来源、权利人、许可或书面授权；
- `rightsBasisType` 使用受控的权利依据类型，而不是 `unverified`；
- `evidencePath` 与 `evidenceSha256` 指向私有权利证据并通过仓库模式的文件、哈希和
  重解析点检查；私有证据本身不会进入安装包；
- `permissionExpiresAt` 为空（长期有效）或仍在有效期内；
- `redistributionAllowed` 为 `true`；
- `allowedDistributionScopes` 包含 `official-binary`；
- 已记录审核人和审核日期。
- 正式载荷包含通过状态的 `THIRD-PARTY-MEDIA-AUDIT.json`，且报告明确记录
  `mode: payload` 与已启用再分发权限检查。

## 0.4.8.2 与 0.4.8.3 测试版例外

0.4.8.2 与 0.4.8.3 测试版保留现有舰船图片和星系地图，以保持当前客户端体验。这些第三方图片的
来源与再分发授权尚未完成核实；将它们列入这两个版本不代表 StarBridge、作者或贡献者拥有其
版权，也不代表已取得原权利人的许可。

本例外只适用于 0.4.8.2 与 0.4.8.3，并在 0.4.8.3 后结束。随包审计会把权利状态明确记录为
`unverified-distribution-exception`，同时继续核验文件路径、大小和 SHA-256，不会把
完整性校验伪装成权利许可。相关权利仍归各自权利人所有；收到有效权利主张或移除请求后，
这些图片可能在后续版本中被替换或移除。0.4.8.4 起默认恢复再分发权限门禁，除非另有新的、
明确且可审计的决定。

来源或再分发权仍为待确认状态的图片，可以保留在私有工作区中继续整理和替换；除上述
仅限 0.4.8.2 与 0.4.8.3 的明确例外外，正式发布流程会主动阻止它们进入公开安装包。媒体审计报告
是正式载荷和发布证据的必需材料，不能以人工确认或仅提供清单代替。公开仓库只提供清单格式、校验工具和权利边界说明，
不提供这些原图。

官方客户端通过清单中的稳定舰船代码与资源键寻找图片，不依赖受限的舰船资料表，也不会
用模糊匹配猜测图片。清单存在冲突或格式异常时，图片索引会整体拒绝加载，界面回退到默认
占位图。媒体清单在应用进程首次使用时载入；替换官方媒体包后需要重新启动应用，才能读取
新的清单与图片。

图片原权利人的权利不受 StarBridge 开放源码许可影响。清单中的哈希和路径仅用于核验
官方客户端内容，不构成对图片版权、商标或其他权利的主张。

## Third-party media

The Apache-2.0 source distribution does not include the original ship images
or system maps. An official binary may contain only media that is declared in
the exact hash manifest and has a reviewed source record that explicitly
permits `official-binary` redistribution.

An approved source must use a controlled, redistributable `rightsBasisType`
and register both `evidencePath` and `evidenceSha256`. Repository-mode audits
verify the private evidence file, its SHA-256, and every path component;
expired permissions are rejected. Payload-mode audits validate the same
registration fields without requiring the private evidence file to be
distributed in the installer.

Every official payload must also include `THIRD-PARTY-MEDIA-AUDIT.json` from a
passing payload-mode audit with redistribution-permission enforcement enabled.
The report is required release evidence and must match the bundled manifest.

### StarBridge 0.4.8.2 and 0.4.8.3 test-release exception

The 0.4.8.2 and 0.4.8.3 test builds retain the existing ship images and system
maps to preserve the current client experience. Their provenance and
redistribution authorization have not been verified. Inclusion does not assert
ownership or permission. The bundled audit records
`rightsStatus: unverified-distribution-exception` while continuing to verify
paths, byte lengths, and SHA-256 hashes.

This exception applies only to 0.4.8.2 and 0.4.8.3 and ends after 0.4.8.3.
Rights remain with their respective owners, and affected media may be removed
or replaced after a valid rights claim or removal request. Version 0.4.8.4 and
later fail closed on redistribution rights unless a new explicit and auditable
decision is made.

Media with unknown provenance may remain in the private working collection for
review or replacement, but it must not pass the official release gate except
under the explicit 0.4.8.2 and 0.4.8.3 exception described above. The
copyright and other rights in third-party media remain with their respective
owners.

The official client resolves images from stable vehicle-code and asset-key
entries in the manifest, without requiring the restricted ship catalogue or
using fuzzy runtime matching. Conflicting or malformed lookup entries cause the
media index to fail closed and the interface to use its normal placeholder.
Because the manifest is cached on first use, the application must be restarted
after replacing an official media pack.

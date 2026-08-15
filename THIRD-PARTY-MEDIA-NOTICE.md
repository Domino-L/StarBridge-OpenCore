# 第三方媒体说明

StarBridge 的 Apache-2.0 开放源码包不包含舰船缩略图、舰船详情图和星系地图原图。
这些图片即使出现在 StarBridge 的内部工作区或官方客户端中，也不会因此自动采用 Apache-2.0。

## 0.6.4.1 公开载荷

0.6.4.1 的公开安装包和更新包不包含来源或再分发权尚未核实的第三方舰船图片和星系地图。
对应页面可能显示应用自带占位图，不影响账号、舰队、房间、通讯和浮层的主要功能。

每个正式载荷必须包含通过状态的 `THIRD-PARTY-MEDIA-AUDIT.json`。对 0.6.4.1，该报告必须记录：

- `mode: payload`；
- `rightsStatus: not-included`；
- 受管媒体文件数为零；
- 受管媒体字节数为零；
- 载荷中不存在媒体登记文件或受管媒体目录。

## 未来媒体的准入条件

官方客户端只有在同时满足以下条件时，才可以恢复第三方媒体：

- 图片列入 `third-party-media-manifest.json`，且文件路径、大小和 SHA-256 完全一致；
- `third-party-media-sources.json` 中记录可追溯的来源、权利人、许可或书面授权；
- `rightsBasisType` 使用受控的可再分发权利依据类型，而不是 `unverified`；
- `evidencePath` 与 `evidenceSha256` 指向私有权利证据并通过审计；
- `permissionExpiresAt` 为空（长期有效）或仍在有效期内；
- `redistributionAllowed` 为 `true`；
- `allowedDistributionScopes` 包含 `official-binary`；
- 已记录审核人和审核日期。

来源或再分发权仍为待确认状态的图片，可以保留在私有工作区中继续整理和替换；
正式发布流程会主动阻止它们进入公开安装包。媒体审计报告是正式载荷和发布证据的必需材料，
不能以人工确认或仅提供清单代替。

图片原权利人的权利不受 StarBridge 开放源码许可影响。清单中的哈希和路径仅用于核验官方客户端内容，
不构成对图片版权、商标或其他权利的主张。

## Third-party media

The Apache-2.0 source distribution does not include original ship images or
system maps. StarBridge 0.6.4.1 public installers and update archives also omit
all third-party media whose provenance or redistribution rights have not been
verified. The client may display built-in placeholders where no approved image
is available.

Every official 0.6.4.1 payload must include a passing
`THIRD-PARTY-MEDIA-AUDIT.json` with `mode: payload`,
`rightsStatus: not-included`, zero managed files, and zero managed bytes. The
release gate also rejects media registration files and managed media
directories from the payload.

Future media may enter an official binary only when it is declared in the
exact-hash manifest and has a reviewed source record that explicitly permits
`official-binary` redistribution. Repository audits verify the private
evidence file, its SHA-256, and every path component; expired permissions are
rejected. Payload audits validate the same registration fields without
requiring private evidence to be distributed.

Media with unknown provenance may remain in the private working collection for
review or replacement, but it must not pass the official release gate. The
copyright and other rights in third-party media remain with their respective
owners.

# 核验 StarBridge Release

请只核验并运行来自
[StarBridge-OpenCore Releases](https://github.com/Domino-L/StarBridge-OpenCore/releases)
的资产。版本页、tag、文件哈希和 Windows 签名共同构成核验链；只看到相同文件名并不能证明文件可信。

## 1. 核验精确 tag 和 Release 资产

安装 [GitHub CLI](https://cli.github.com/) 后，将下面的版本替换为准备下载的精确 tag：

```powershell
$repo = "Domino-L/StarBridge-OpenCore"
$tag = "v0.4.8.1"

gh release verify $tag --repo $repo
gh release download $tag --repo $repo --dir ".\release"
gh release verify-asset $tag ".\release\StarBridge-0.4.8.1-win-x64-update.zip" --repo $repo
```

`gh release verify` 应确认该 Release 已不可变，`gh release verify-asset` 应确认本地文件与该精确
Release 的资产一致。任一命令失败时，不要继续运行该文件。GitHub 的官方说明见
[Verifying the integrity of a release](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/verify-release-integrity)。

## 2. 核对下载清单

Release 随附的 `SHA256SUMS.txt` 列出安装器、更新包和更新清单的 SHA-256。示例：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath ".\release\StarBridge-0.4.8.1-win-x64-setup.exe"
```

输出必须与 `SHA256SUMS.txt` 中同名文件的值完全一致。更新 ZIP 内另有
`PAYLOAD-SHA256SUMS.txt`；它覆盖包内除清单自身以外的每一个文件。

## 3. 核验 Windows Authenticode

```powershell
Get-AuthenticodeSignature -LiteralPath ".\release\StarBridge-0.4.8.1-win-x64-setup.exe" |
    Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate
```

正式发布资产的 `Status` 必须为 `Valid`。显示 `NotSigned`、`UnknownError`、证书无效或签名者异常时，
不要安装。SHA-256 只能说明文件是否变化；Authenticode 还用于核验 Windows 发布者签名。

## 4. 检查 SBOM 与构建来源

解压更新包后检查：

- `SBOM.cdx.json`：CycloneDX 1.5 软件物料清单；
- `third-party-packages.json` 与 `licenses/`：第三方组件版本及随包许可；
- `third-party-media-manifest.json`、`third-party-media-sources.json` 与
  `THIRD-PARTY-MEDIA-NOTICE.md`：官方客户端媒体的精确哈希、来源记录与分发边界；
- `THIRD-PARTY-MEDIA-AUDIT.json`：正式载荷媒体审计证据；其状态必须为 `passed`，
  `mode` 必须为 `payload`，并且必须启用再分发权限检查；
- `BUILD-PROVENANCE.json`：版本、精确 `releaseTag`、源提交、源树、公开源提交、SDK、RID 和构建时间；
- `PAYLOAD-SHA256SUMS.txt`：上述材料和应用文件都必须被覆盖。

正式发布的 provenance 应满足 `sourceDirty: false`，`releaseTag` 应与正在核验的 tag 完全一致。
其中 `officialMedia.auditSha256`、文件数量和字节数还必须与
`THIRD-PARTY-MEDIA-AUDIT.json` 及媒体清单一致。
仓库提供的审计脚本会同时检查这些关系、拒绝 server/private/受限数据，并要求官方客户端媒体与已审核
清单逐项一致；它还可以强制检查 `Star Bridge.exe` 的 Authenticode：

```powershell
Expand-Archive ".\release\StarBridge-0.4.8.1-win-x64-update.zip" ".\payload"
& ".\scripts\Test StarBridge Binary Distribution.ps1" `
    -PayloadRoot ".\payload" `
    -ArchivePath ".\release\StarBridge-0.4.8.1-win-x64-update.zip" `
    -ExpectedVersion "0.4.8.1" `
    -RequireAuthenticode
```

公开 workflow `.github/workflows/binary-release-audit.yml` 也执行同一审计。手动运行时必须填写精确
`release_tag`；workflow 会核验 immutable Release 和资产，再上传 `BINARY-AUDIT-REPORT.json`。

## 可验证范围

公开仓库可以核验 Release 与精确 tag 的绑定、发布资产摘要、随包许可、SBOM、provenance、payload
哈希和签名，也提供可独立构建的开放核心。

完整官方二进制还可能包含未公开的商业外观实现。由于这些源文件不在公开仓库中，不能宣称公开仓库
可以位级复现完整官方二进制（the complete official binary is not bit-for-bit reproducible from this
public repository）；公开构建与官方完整二进制的哈希不同并不自动表示发布资产被篡改。应以
immutable Release、Release 资产摘要、Authenticode 和随包审计材料组成的验证链为准。

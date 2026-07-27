# 核验 StarBridge Release

请只运行来自 [StarBridge-OpenCore Releases](https://github.com/Domino-L/StarBridge-OpenCore/releases) 或 [星海舰桥官网](https://scstarbridge.com/) 的安装器。相同文件名不能证明文件可信。

## 0.4.8.2 的签名状态

0.4.8.2 是取得代码签名证书前明确发布的未签名测试版。Windows 可能显示“未知发布者”，`Get-AuthenticodeSignature` 也可能返回 `NotSigned`；这属于本版已公开说明的状态，不代表文件本身已经通过发布者身份验证。

如果你不能接受未签名程序的风险，请等待后续带可信 Authenticode 签名的版本。决定安装 0.4.8.2 时，至少完成下面的 GitHub Release、SHA-256、更新清单和构建证据核验。

## 1. 核验精确 tag 和 Release 资产

安装 [GitHub CLI](https://cli.github.com/) 后运行：

```powershell
$repo = "Domino-L/StarBridge-OpenCore"
$tag = "v0.4.8.2"

gh release verify $tag --repo $repo
gh release download $tag --repo $repo --dir ".\release"
gh release verify-asset $tag ".\release\StarBridge-0.4.8.2-win-x64-update.zip" --repo $repo
```

`gh release verify` 应确认 Release 已不可变，`gh release verify-asset` 应确认本地文件属于该精确 Release。任一命令失败时不要继续运行文件。

## 2. 核对 SHA-256

Release 随附的 `SHA256SUMS.txt` 覆盖安装器、更新包、更新清单和审计材料：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath ".\release\StarBridge-0.4.8.2-win-x64-setup.exe"
```

输出必须与 `SHA256SUMS.txt` 中同名文件的值完全一致。更新 ZIP 内的 `PAYLOAD-SHA256SUMS.txt` 还覆盖包内文件。

## 3. 查看 Authenticode 证据

```powershell
Get-AuthenticodeSignature -LiteralPath ".\release\StarBridge-0.4.8.2-win-x64-setup.exe" |
    Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate
```

0.4.8.2 可能显示 `NotSigned`。Release 中的 `StarBridge-0.4.8.2-authenticode-status.json` 和许可证据包内的 `AUTHENTICODE-STATUS.json` 会如实记录主程序、完整安装包和在线安装器的实际状态。后续签名版本应显示 `Valid` 并包含可信时间戳。

## 4. 检查 SBOM 与构建来源

解压更新包后检查：

- `SBOM.cdx.json`：软件物料清单；
- `third-party-packages.json` 与 `licenses/`：第三方组件及随包许可；
- `third-party-media-manifest.json`：官方客户端媒体文件的路径与摘要清单；
- `THIRD-PARTY-MEDIA-AUDIT.json`：官方客户端媒体审计证据；0.4.8.2 应为 `passed`，同时 `rightsStatus` 必须如实为 `unverified-distribution-exception`，而不是已获授权；
- `BUILD-PROVENANCE.json`：版本、tag、私有源提交、公开源提交、SDK、RID 和构建时间；
- `PAYLOAD-SHA256SUMS.txt`：载荷内文件摘要。

正式发布的 provenance 应满足 `sourceDirty: false`，`releaseTag` 应与正在核验的 tag 完全一致。0.4.8.2 可在不要求 Authenticode 的前提下复跑公开审计：

```powershell
Expand-Archive ".\release\StarBridge-0.4.8.2-win-x64-update.zip" ".\payload"
& ".\scripts\Test StarBridge Binary Distribution.ps1" `
    -PayloadRoot ".\payload" `
    -ArchivePath ".\release\StarBridge-0.4.8.2-win-x64-update.zip" `
    -ExpectedVersion "0.4.8.2" `
    -AllowUnverifiedThirdPartyMediaTestRelease
```

公开 workflow `.github/workflows/binary-release-audit.yml` 也执行同一载荷审计。

## 可验证范围

公开仓库可以核验 Release 与 tag 的绑定、资产摘要、随包许可、SBOM、provenance、载荷哈希和开放核心代码。正式版本采用 GitHub `immutable Release` 固定资产集合。完整官方客户端还可能包含未公开的商业外观实现，因此公开源码不能做到 `bit-for-bit reproducible`，也不能位级复现完整官方二进制。

对 0.4.8.2 而言，GitHub 不可变 Release、SHA-256、签名更新清单和构建审计共同降低下载被替换的风险，但不能提供 Authenticode 发布者身份保证。后续取得证书后，可信签名会重新成为默认发布门槛。

0.4.8.2 的媒体审计能证明随包图片与公开清单的路径、大小和 SHA-256 一致，但不能证明来源待核实图片已经获得再分发授权。该限制是本版发布证据的一部分，不应被省略或改写为“媒体已授权”。

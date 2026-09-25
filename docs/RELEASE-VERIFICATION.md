# 核验 StarBridge Release

当前公开测试版为 0.7.0.2。版本记录按产品版本统一展示，不区分实现技术。

请只运行来自 [StarBridge-OpenCore Releases](https://github.com/Domino-L/StarBridge-OpenCore/releases)
或 [星海舰桥官网](https://scstarbridge.com/) 的安装器。相同文件名不能证明文件可信。

## 0.7.0.2 的签名状态

0.7.0.2 的主程序、更新助手和完整安装器均必须具有可信 Windows Authenticode
签名和时间戳。如果 Windows 显示“未知发布者”，或 `Get-AuthenticodeSignature`
不是 `Valid`，请不要安装或运行该文件。

## 0.7.0.2 完整安装器

本版使用完整安装器，不使用历史版本的 `win-x64-update.zip`。正式下载文件为：

- 官网文件：`StarBridge-0.7.0.2-20260924-03-win-x64-setup.exe`
- GitHub 附件：`StarBridge-0.7.0.2-win-x64-setup.exe`
- 两者 SHA-256：`26a3b9c0850e058f67c249256732c891f82b37f12b0affa7048f3385617a5110`

```powershell
Get-FileHash -Algorithm SHA256 .\StarBridge-0.7.0.2-win-x64-setup.exe
Get-AuthenticodeSignature .\StarBridge-0.7.0.2-win-x64-setup.exe |
    Format-List Status, SignerCertificate, TimeStamperCertificate
```

摘要必须完全一致，签名必须是 `Valid` 且有可信时间戳。应用内更新另行验证
带签名的安装清单，其版本、地址、摘要及公告内容都属于验证范围。
GitHub Release 发布后，还应运行 `gh release verify v0.7.0.2 --repo Domino-L/StarBridge-OpenCore`
与相应的 `gh release verify-asset`；草稿或未通过不可变验证不等于已完成 GitHub 发布。

当前 OpenCore `main` 会继续演进，不是完整官方安装包的逐字节构建证明。
下列 ZIP、SBOM 和载荷审计命令适用于随附这些证据的历史发行包，不能声称
已核验不存在的当前版附件，也不能把旧报告用于新的安装器。

## 历史 ZIP 发行包核验（以 0.6.6 为例）

### 1. 核验精确 tag 和 Release 资产

安装 [GitHub CLI](https://cli.github.com/) 后运行：

```powershell
$repo = "Domino-L/StarBridge-OpenCore"
$tag = "v0.6.6"

gh release verify $tag --repo $repo
gh release download $tag --repo $repo --dir ".\release"
gh release verify-asset $tag ".\release\StarBridge-0.6.6-win-x64-update.zip" --repo $repo
```

`gh release verify` 应确认 Release 已不可变，`gh release verify-asset` 应确认本地文件属于
该精确 Release。任一命令失败时不要继续运行文件。

## 2. 核对 SHA-256

Release 随附的 `SHA256SUMS.txt` 覆盖安装器、更新包、更新清单和审计材料：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath ".\release\StarBridge-0.6.6-win-x64-setup.exe"
```

输出必须与 `SHA256SUMS.txt` 中同名文件的值完全一致。更新 ZIP 内的
`PAYLOAD-SHA256SUMS.txt` 还覆盖包内文件。

## 3. 验证 Authenticode

```powershell
Get-AuthenticodeSignature -LiteralPath ".\release\StarBridge-0.6.6-win-x64-setup.exe" |
    Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate
```

`Status` 必须是 `Valid`，且 `SignerCertificate` 和 `TimeStamperCertificate` 都必须存在。
Release 中的 `StarBridge-0.6.6-authenticode-status.json` 和许可证据包内的
`AUTHENTICODE-STATUS.json` 应对主程序、完整安装器和在线安装器全部记录为有效。

## 4. 检查 SBOM、构建来源和媒体边界

解压更新包后检查：

- `SBOM.cdx.json`：软件物料清单；
- `third-party-packages.json` 与 `licenses/`：第三方组件及随包许可；
- `third-party-media-manifest.json`：如载荷不包含已批准媒体，该登记文件也不应进入正式载荷；
- `THIRD-PARTY-MEDIA-AUDIT.json`：应为 `passed`，且 `rightsStatus` 应为 `not-included`、
  文件数和字节数均为零；
- `BUILD-PROVENANCE.json`：版本、tag、私有源提交、公开源提交、SDK、RID 和构建时间；
- `PAYLOAD-SHA256SUMS.txt`：载荷内文件摘要。

正式发布的 provenance 应满足 `sourceDirty: false`，`releaseTag` 应与正在核验的 tag
完全一致。可以复跑公开载荷审计：

```powershell
Expand-Archive ".\release\StarBridge-0.6.6-win-x64-update.zip" ".\payload"
& ".\scripts\Test StarBridge Binary Distribution.ps1" `
    -PayloadRoot ".\payload" `
    -ArchivePath ".\release\StarBridge-0.6.6-win-x64-update.zip" `
    -ExpectedVersion "0.6.6" `
    -RequireAuthenticode
```

公开 workflow `.github/workflows/binary-release-audit.yml` 也执行同一载荷审计。

## 可验证范围

公开仓库可以核验 Release 与 tag 的绑定、资产摘要、Windows 数字签名、随包许可、
SBOM、provenance、载荷哈希和开放核心代码。正式版本采用 GitHub `immutable Release`
固定资产集合。完整官方客户端还可能包含未公开的商业外观实现，因此公开源码不能
对完整官方二进制做到 `bit-for-bit reproducible`；这不影响上述开放组件和发布证据的独立核验。

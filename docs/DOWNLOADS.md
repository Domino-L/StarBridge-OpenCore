# 下载帮助

本文说明 0.7.2.1 的下载与核验方法。版本发布状态以官网公告和正式 GitHub Release 为准。
修复应用内更新无法启动的问题和舰船显示问题。0.7.1、0.7.2 用户请下载完整安装包手动安装，无需卸载或清空个人数据。

## 推荐下载方式

- [官网下载页](https://scstarbridge.com/)：查看当前公告和校验信息。
- [0.7.2.1 完整安装包](https://api.scstarbridge.com/downloads/StarBridge-0.7.2.1-20261103-01-win-x64-setup.exe)：下载后先核验，再离线安装。
- [0.7.2 完整安装包](https://api.scstarbridge.com/downloads/StarBridge-0.7.2-20261101-01-win-x64-setup.exe)：上一已发布版本，下载后可离线安装。
- [全部版本](https://github.com/Domino-L/StarBridge-OpenCore/releases)：查看版本说明、历史安装包和校验文件。

GitHub 自动生成的 “Source code” 压缩包只包含开放核心源码，不是应用安装包。普通用户请选择名称以 `.exe` 结尾的安装器。

## 校验下载文件

0.7.2.1 安装器大小为 **411803296 字节**，SHA-256 为
`AD9CF2A7CE957CB8E1895AAA21530F148913870269353665446E9170E80828C8`。
请逐项核对大小、摘要、发布者签名和时间戳，完整步骤见 [Release 核验指南](RELEASE-VERIFICATION.md)。

每个正式 Release 会附带 `SHA256SUMS.txt`。在 PowerShell 中运行：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath ".\StarBridge-win-x64-setup.exe"
```

将输出的哈希与 `SHA256SUMS.txt` 中对应文件的值比较。两者不一致时不要运行该文件，请重新下载并提交反馈。

## 常见情况

### Windows 显示“未知发布者”

官方主程序、更新助手和完整安装器均要求可信 Windows 数字签名和时间戳。
如果安装时显示“未知发布者”或签名不是有效状态，请不要继续；重新从官方渠道下载并提交反馈。

### 安装包中的第三方图片

公开源码不包含来源或再分发权尚未核实的第三方舰船图片和星系地图。
官方安装包的品牌、专有外观和可选素材适用随包许可；不要将源码许可理解为这些素材的再分发授权。仅核验当前 Release 实际随附的证据，不将历史素材报告套用于本版。

### 在线安装器无法下载

可以改用完整安装包。若完整安装包也无法下载，请查看 [Issues](https://github.com/Domino-L/StarBridge-OpenCore/issues) 中是否已有服务状态说明。

### 安装后无法启动

重新下载完整安装包并核对 SHA-256。仍无法启动时，请在应用内或 [问题反馈](https://github.com/Domino-L/StarBridge-OpenCore/issues/new/choose) 中说明 Windows 版本、应用版本和复现步骤。

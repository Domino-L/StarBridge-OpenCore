# 下载帮助

## 推荐下载方式

- [在线安装器](https://github.com/Domino-L/StarBridge-OpenCore/releases/latest/download/StarBridge-online-setup.exe)：自动获取并安装最新版本。
- [完整安装包](https://github.com/Domino-L/StarBridge-OpenCore/releases/latest/download/StarBridge-win-x64-setup.exe)：下载后可离线安装。
- [全部版本](https://github.com/Domino-L/StarBridge-OpenCore/releases)：查看版本说明、历史安装包和校验文件。

GitHub 自动生成的 “Source code” 压缩包只包含开放核心源码，不是应用安装包。普通用户请选择名称以 `.exe` 结尾的安装器。

## 校验下载文件

每个正式 Release 会附带 `SHA256SUMS.txt`。在 PowerShell 中运行：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath ".\StarBridge-win-x64-setup.exe"
```

将输出的哈希与 `SHA256SUMS.txt` 中对应文件的值比较。两者不一致时不要运行该文件，请重新下载并提交反馈。

## 常见情况

### Windows 显示“未知发布者”

当前测试版可能尚未使用受公众信任的 Windows 代码签名证书。请确认下载地址属于本仓库 Releases 或星海舰桥官网，并核对 SHA-256。

### 在线安装器无法下载

可以改用完整安装包。若完整安装包也无法下载，请查看 [Issues](https://github.com/Domino-L/StarBridge-OpenCore/issues) 中是否已有服务状态说明。

### 安装后无法启动

重新下载完整安装包并核对 SHA-256。仍无法启动时，请在应用内或 [问题反馈](https://github.com/Domino-L/StarBridge-OpenCore/issues/new/choose) 中说明 Windows 版本、应用版本和复现步骤。

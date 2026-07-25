# 星海舰桥 StarBridge

面向《星际公民》玩家社区的 Windows 舰队协作工具。当前为公开测试版。

星海舰桥提供舰队与小队管理、组队房间、好友与通讯、个人资料、机库整理，以及可自定义的游戏浮层。应用只读你主动选择的 `Game.log`，不会向游戏注入代码、读取游戏内存或修改游戏文件。

> 星海舰桥是玩家社区独立开发的第三方工具，与 Cloud Imperium Games、Roberts Space Industries 无隶属、授权或背书关系。

## 下载与安装

支持 Windows 10 / 11 x64。

| 下载方式 | 适合场景 |
| --- | --- |
| [下载在线安装器](https://github.com/Domino-L/StarBridge-OpenCore/releases/latest/download/StarBridge-online-setup.exe) | 推荐。安装器体积较小，会自动获取并安装最新版本。 |
| [下载完整安装包](https://github.com/Domino-L/StarBridge-OpenCore/releases/latest/download/StarBridge-win-x64-setup.exe) | 适合离线安装，或需要保留完整安装文件时使用。 |
| [查看全部版本](https://github.com/Domino-L/StarBridge-OpenCore/releases) | 查看更新说明、历史版本和 SHA-256 校验文件。 |

当前安装包可能尚未使用受公众信任的 Windows 代码签名证书，因此 SmartScreen 可能显示“未知发布者”。请只从本仓库的 Releases 或 [星海舰桥官网](https://scstarbridge.com/) 下载，并在需要时核对 Release 中的 `SHA256SUMS.txt`。

安装与首次使用说明见 [开始使用](docs/GETTING_STARTED.md)。如果下载或更新失败，请先查看 [下载帮助](docs/DOWNLOADS.md)。

## 主要功能

- 舰队资料、成员、身份组、权限、小队、公告与舰队通讯；
- 组队房间、三级玩法标签、申请审核、房间邀请与房间聊天；
- 好友、私信、资料查看及舰队或房间邀请卡片；
- 个人资料、机库扫描、舰船概览、游戏定位与可见性设置；
- 游戏浮层、布局编辑、事件通知、虚拟准星、预设与外观；
- 只读 `Game.log`，辅助识别游戏状态、飞船、地点与量子航行信息。

日志信息可能因游戏版本、网络状态或日志完整性而延迟、缺失或识别错误，请勿将浮层内容作为唯一行动依据。

## 帮助与反馈

- 使用问题或功能建议：[提交反馈](https://github.com/Domino-L/StarBridge-OpenCore/issues/new/choose)
- 已知问题与处理进度：[查看 Issues](https://github.com/Domino-L/StarBridge-OpenCore/issues)
- 安全问题：请按 [安全说明](SECURITY.md) 私下报告，不要在公开 Issue 中附带个人日志、账号信息或令牌。
- QQ 测试群：`534268220`

更多联系方式和产品说明见 [星海舰桥官网](https://scstarbridge.com/)。

## 开放核心源码

本仓库同时承担星海舰桥的公开下载、版本说明和开放核心源码维护。

当前 Apache-2.0 开放范围包括：

- 只读 `Game.log` 监听与事件解析；
- 飞船、地点、量子航行和在线状态推断；
- 核心协作数据契约；
- 公开算法的回归测试与说明文档。

桌面应用、托管服务、部署配置、商业授权实现，以及“夜影”和 Verdict 等可选商业外观源码不在 Apache-2.0 开放范围内。Releases 中提供的是可直接安装的完整桌面应用，其二进制分发边界见 [完整应用与源码许可](BINARY-DISTRIBUTION-NOTICE.md)。

开发者可查看 [参与贡献](CONTRIBUTING.md) 和 [Game.log 识别算法](docs/GAME_LOG_LISTENING_ALGORITHM.md)。

### 构建开放核心

需要 .NET 8 SDK：

```powershell
dotnet build StarBridge.sln
dotnet run --project StarBridge.Core.Tests/StarBridge.Core.Tests.csproj
```

## 许可与名称

本仓库中明确发布的开放核心源码采用 [Apache License 2.0](LICENSE)。产品名称、标志、应用图标、商业外观和第三方游戏素材不随 Apache-2.0 授权，详见 [TRADEMARKS.md](TRADEMARKS.md) 与 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

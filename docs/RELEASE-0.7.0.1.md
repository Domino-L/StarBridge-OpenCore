# 星海舰桥 0.7.0.1 发布核验

本版本使用官方签名完整安装器，不提供旧式更新 ZIP 或新的在线引导安装器。
保留信息浮层，不提供菜单浮层及其设置和快捷键入口。

## 下载与校验

请从 [官网](https://scstarbridge.com/) 或
[v0.7.0.1 Release](https://github.com/Domino-L/StarBridge-OpenCore/releases/tag/v0.7.0.1) 下载。

文件：`StarBridge-0.7.0.1-win-x64-setup.exe`，456,492,200 字节。

SHA-256：`f00f028f32be3233111edb77809380d24215a01288b3f0cc678e5b297bb7a129`。

```powershell
Get-FileHash .\StarBridge-0.7.0.1-win-x64-setup.exe -Algorithm SHA256
Get-AuthenticodeSignature .\StarBridge-0.7.0.1-win-x64-setup.exe |
    Format-List Status, SignerCertificate, TimeStamperCertificate
```

签名应为 `Valid`，发布者为 `ruiyang lyu`，并有有效时间戳。
官网文件名附带构建标识，文件内容与 GitHub 附件完全相同。

## 已验证范围

- 正式签名包的真实升级、无效清单拒绝、安装失败回滚、更新助手中断恢复、启动失败回滚。
- 正式安装的全部 1856 个载荷文件与发布候选一致，启动回执通过。
- 隔离卸载保留测试数据，日常账号资料未被测试修改。
- 更新清单签名有效，公告包含新增、优化、修复、使用须知。
- 公开源码安全、第三方许可、编译与控制台回归通过。

公开源码遵守仓库既有开源边界，不包含托管服务、商业实现或受限游戏素材；
不是完整发行二进制的逐字节可复现源码。合作开发的客户端源码由授权协作仓库提供。

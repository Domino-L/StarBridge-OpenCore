# 完整应用与源码许可

GitHub Releases 中的安装器用于向用户分发完整的星海舰桥桌面应用。

0.5.0 的主程序、完整安装器和在线安装器均必须具有可信 Windows Authenticode
签名和时间戳。用户应只从官方网页或本仓库不可变 Release 下载，并核对
`SHA256SUMS.txt`、签名更新清单和 `AUTHENTICODE-STATUS.json`。

仓库内明确发布的桌面客户端与核心代码采用 Apache License 2.0。Release 安装包还可能包含
未在本仓库公开的商业授权实现和可选商业外观，因此安装包整体不因存放在本仓库而全部转为 Apache-2.0。

0.5.0 官方载荷不包含来源或再分发权尚未核实的第三方舰船图片和星系地图。
正式载荷必须随附 `THIRD-PARTY-MEDIA-AUDIT.json`；对无媒体载荷，该报告应记录
`rightsStatus: not-included`、零文件和零字节。

“夜影”、Verdict 及后续可选商业外观不会改变基础功能、数据权限或协作能力。其源码和授权实现
不属于本仓库的 Apache-2.0 开放范围。

官方完整应用中的专有组件适用随安装包提供的
[`OFFICIAL-BINARY-LICENSE.txt`](docs/OFFICIAL-BINARY-LICENSE.txt)，其个人权利人和许可方为 Ruiyang Lyu。
商业外观的使用资格与获得授权的 StarBridge 账号绑定。

当前免费测试版不包含应用内付费购买。完整客户端条款版本为 `2026-07-27-v2`；应用会保存接受时间、
应用版本和条款文件 SHA-256，以便在条款发生实质变化时重新提示。

未经书面许可，不得镜像、重新托管或重新分发完整的官方安装包、更新包或便携包；可以分享未经修改的
StarBridge 官方网页、发布页或官方下载链接。该限制只针对完整官方包这一集合及其中的专有组件，
不限制依照 Apache License 2.0 单独复制、修改或再分发开放组件。

产品名称、标志、应用图标和第三方游戏素材的使用边界见 [TRADEMARKS.md](TRADEMARKS.md)、
[ASSET_POLICY.md](ASSET_POLICY.md)、[THIRD-PARTY-MEDIA-NOTICE.md](THIRD-PARTY-MEDIA-NOTICE.md)
与 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

第三方软件组件及其完整许可文本见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) 与 `licenses/`。
游戏数据和翻译映射的来源边界见 [DATA_RIGHTS.md](DATA_RIGHTS.md)。

Nothing in this notice limits or replaces any rights granted under the Apache
License 2.0 for the Open Components.

本说明用于解释开放源码与完整二进制包的组成；具体的个人设备使用、备份、账号绑定、更新、终止、
逆向工程法定例外、免责声明和第三方组件条款以随包的正式许可协议为准。

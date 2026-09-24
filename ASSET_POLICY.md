# 素材与许可边界

公开源码、运行时品牌文件、字体与第三方游戏媒体采用不同的权利边界。

## 明确列出的运行时文件

完整文件列表、SHA-256 与许可路径见 `client-assets.json`。导出仅接受逐项列出的文件，
不会递归公开素材目录。新增或修改文件必须同时更新来源与审查记录。

- StarBridge 新版运行时图标、主题小图标和字标：适用
  `StarBridge.Flutter/assets/brand/LICENSE.txt`，仅用于获取、构建和测试未修改的
  官方源码。分支或修改版必须更换品牌，不采用 Apache-2.0。
- SCM 标记：仅按已批准集成范围标识 SCM 授权和数据来源，SCM 保留权利。
  来源、哈希和转换记录见 `docs/brand-assets/scm/README.md`；不授权作为其他产品品牌。
- Adobe Source Sans 3、Source Han Sans CN、Source Code Pro：保留 SIL OFL 1.1
  原文，位于 `StarBridge.Flutter/assets/font-licenses/`。
- Dart/Flutter 依赖许可：`flutter-packages.json` 与 `licenses/flutter/`。
  SDK 本身适用其上游许可；构建时由官方 Flutter SDK 提供。
- .NET 依赖许可：`third-party-packages.json` 与 `licenses/`。

产品名称和商标规则另见 `TRADEMARKS.md`。开放源码许可不覆盖品牌权利。

## 不进入公开源码

可编辑品牌母版、高分辨率设计稿、舰船截图、星系地图、背景视频、个人头像、
聊天附件、测试截图、用户缓存、商业外观素材，以及未确认再分发权的游戏媒体，
均不进入公开树。缺少可选媒体时使用既有中性占位，不应复制私人数据来补齐构建。

游戏标识、翻译表和外部数据库内容按 `DATA_RIGHTS.md` 单独审查。
官方二进制所含媒体还需遵守 `THIRD-PARTY-MEDIA-NOTICE.md` 的发布审计。

新增图片、图标、字体、音频或视频必须说明来源和许可。未审核的文件不得加入白名单。

import 'package:flutter/material.dart';

import '../appearance/appearance_scope.dart';
import 'brand_lockup_spec.dart';

class BrandLockup extends StatelessWidget {
  const BrandLockup({required this.scale, this.showWordmark = true, super.key});

  final BrandLockupScale scale;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final spec = BrandLockupResolver.resolve(
      locale: Localizations.localeOf(context),
      surfaceBrightness: Theme.of(context).brightness,
      scale: scale,
    );
    // 节日期间星标换成节日版；字标不动。
    final markAsset =
        AppearanceScope.of(context).mark?.resolve(
          surfaceBrightness: Theme.of(context).brightness,
          physicalSize:
              spec.markSize * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
        ) ??
        spec.markAsset;
    return Padding(
      padding: spec.safePadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 原图比显示大很多倍。high 只适合放大，菜单浮层用的 Skia 缩小时会起锯齿、细线断开；
          // 主窗口的 Impeller 下 medium 和 high 画出来一样。
          Image.asset(
            markAsset,
            width: spec.markSize,
            height: spec.markSize,
            filterQuality: FilterQuality.medium,
          ),
          if (showWordmark && spec.wordmarkAsset != null) ...[
            SizedBox(width: spec.gap),
            Flexible(
              child: Image.asset(
                spec.wordmarkAsset!,
                height: spec.wordmarkHeight,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

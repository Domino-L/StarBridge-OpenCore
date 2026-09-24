import 'package:flutter/material.dart';

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
    return Padding(
      padding: spec.safePadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            spec.markAsset,
            width: spec.markSize,
            height: spec.markSize,
            filterQuality: FilterQuality.high,
          ),
          if (showWordmark && spec.wordmarkAsset != null) ...[
            SizedBox(width: spec.gap),
            Flexible(
              child: Image.asset(
                spec.wordmarkAsset!,
                height: spec.wordmarkHeight,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.high,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

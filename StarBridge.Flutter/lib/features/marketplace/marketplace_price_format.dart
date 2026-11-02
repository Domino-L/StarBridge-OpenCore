import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_diagonal.dart' show MarketHeadingMark;
import 'marketplace_port.dart' show marketNumber;
import 'marketplace_surfaces.dart' show marketLine;
import 'marketplace_widgets.dart';

/// The SCM site's 价格显示格式, plus "auto": 中文 UI → 万/亿, English → K/M/B.
const marketPriceFormats = ['auto', 'comma', 'intl', 'chinese'];

/// [value] written in [format] for [locale] ('cn', 'hant' or 'en'). Units
/// keep up to four trimmed decimals, so a round price stays exact and short
/// ("100万", "1.25亿", "1M"); below the first unit it is [marketMoney].
String marketPriceIn(
  Object? value, {
  required String format,
  required String locale,
}) {
  final number = marketNumber(value);
  if (number == null || !number.isFinite) return '—';
  final style = format == 'auto'
      ? (locale == 'en' ? 'intl' : 'chinese')
      : format;
  final units = switch (style) {
    'intl' => const [(1e12, 'T'), (1e9, 'B'), (1e6, 'M'), (1e3, 'K')],
    'chinese' when locale == 'hant' => const [
      (1e12, '萬億'),
      (1e8, '億'),
      (1e4, '萬'),
    ],
    'chinese' => const [(1e12, '万亿'), (1e8, '亿'), (1e4, '万')],
    _ => const <(double, String)>[],
  };
  final size = number.abs();
  for (final (scale, unit) in units) {
    if (size < scale) continue;
    final digits = (size / scale)
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return '${number < 0 ? '-' : ''}$digits$unit';
  }
  return marketMoney(number);
}

/// Carries the saved price format to every price under the trading hall.
class MarketPriceFormatScope extends InheritedWidget {
  const MarketPriceFormatScope({
    required this.format,
    required super.child,
    super.key,
  });
  final String format;

  static String of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MarketPriceFormatScope>()
          ?.format ??
      'auto';

  @override
  bool updateShouldNotify(MarketPriceFormatScope old) => format != old.format;
}

/// Display settings, after the SCM site's 显示偏好 → 价格显示格式: one choice,
/// saved on this computer the moment it is picked.
Future<void> showMarketDisplaySettings(
  BuildContext context,
  MarketplaceController c,
) => showDialog<void>(
  context: context,
  builder: (_) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => _DisplaySettings(c),
  ),
);

class _DisplaySettings extends StatelessWidget {
  const _DisplaySettings(this.c);
  final MarketplaceController c;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locale = marketLocale(context);
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: Row(
        children: [
          MarketHeadingMark(),
          const SizedBox(width: 8),
          Text(marketText(context, 'priceFormat')),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              marketText(context, 'priceFormatHint'),
              style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final format in marketPriceFormats) ...[
              _option(context, format, locale),
              const SizedBox(height: 6),
            ],
            if (c.preferencesFailed)
              MarketNotice(
                marketText(context, 'preferencesFailed'),
                retry: c.readPreferences,
              ),
          ],
        ),
      ),
      actions: [
        marketTextAction(
          key: const Key('market-display-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(marketText(context, 'close')),
        ),
      ],
    );
  }

  Widget _option(BuildContext context, String format, String locale) {
    final t = context.tokens;
    final selected = c.priceFormat == format;
    final title = marketText(context, 'priceFormat.$format');
    final description = marketText(context, 'priceFormat.$format.desc');
    final examples = [
      for (final v in const [9500, 1234567, 100000000])
        marketPriceIn(v, format: format, locale: locale),
    ];
    return StarBridgeActionRow(
      controlKey: ValueKey(('market-price-format', format)),
      baseRadius: 0,
      inheritContentStyle: true,
      semanticSelected: selected,
      semanticLabel: '$title. $description. ${examples.join(', ')}',
      onActivate: c.savingPreferences || c.preferencesFailed
          ? null
          : (_, _) => c.setPriceFormat(format),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected ? t.colors.accent.withValues(alpha: .08) : null,
            border: Border(
              left: BorderSide(
                width: 3,
                color: selected ? t.colors.accent : marketLine(context),
              ),
              top: BorderSide(color: marketLine(context)),
              right: BorderSide(color: marketLine(context)),
              bottom: BorderSide(color: marketLine(context)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? t.colors.textPrimary
                            : t.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final example in examples)
                    Text(
                      '¤ $example',
                      style: TextStyle(
                        fontFamily: t.typography.monoFamily,
                        fontSize: 12,
                        color: MarketplacePalette.gold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

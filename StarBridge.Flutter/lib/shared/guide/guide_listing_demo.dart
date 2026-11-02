import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'guide_copy.dart';

/// "How listings work": a self-contained sample of the 4-step publish wizard.
/// It never touches the real wizard or any market port, so nothing can be
/// posted from here (the user asked that guides never cause a real trade).
Future<void> showGuideListingDemo(BuildContext context) =>
    showStarBridgeDialog<void>(context, builder: (_) => const _ListingDemo());

class _ListingDemo extends StatefulWidget {
  const _ListingDemo();
  @override
  State<_ListingDemo> createState() => _ListingDemoState();
}

class _ListingDemoState extends State<_ListingDemo> {
  int _step = 0;
  static const _steps = 4;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    final prefix = 'tour.listing.${_step + 1}';
    final note = copy.maybe('$prefix.note');
    final last = _step == _steps - 1;
    return AlertDialog(
      key: const Key('guide-listing-demo'),
      title: Row(
        children: [
          Flexible(child: Text(copy.text('tour.listing.name'))),
          SizedBox(width: t.space.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.colors.warningSoft,
              borderRadius: BorderRadius.circular(t.shape.radiusSmall),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: t.space.sm,
                vertical: 2,
              ),
              child: Text(
                copy.text('tour.demoBadge'),
                key: const Key('guide-listing-demo-badge'),
                style: text.labelSmall?.copyWith(color: t.colors.warning),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < _steps; i++) ...[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: i == _step
                            ? t.colors.accentSoft
                            : t.surfaces.raised.fill,
                        borderRadius: BorderRadius.circular(
                          t.shape.radiusSmall,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(t.space.xs),
                        child: Text(
                          '${i < _step ? '✓ ' : ''}${i + 1} ${copy.text('tour.listing.step${i + 1}')}',
                          style: text.labelMedium?.copyWith(
                            color: i < _step
                                ? t.colors.success
                                : i == _step
                                ? t.colors.textPrimary
                                : t.colors.textDisabled,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < _steps - 1) SizedBox(width: t.space.xs),
                ],
              ],
            ),
            SizedBox(height: t.space.md),
            _Sample(step: _step, copy: copy),
            SizedBox(height: t.space.md),
            Text(copy.text('$prefix.title'), style: text.titleSmall),
            SizedBox(height: t.space.xxs),
            Text(
              copy.text('$prefix.body'),
              style: text.bodyMedium?.copyWith(color: t.colors.textSecondary),
            ),
            if (note != null) ...[
              SizedBox(height: t.space.xxs),
              Text(
                note,
                style: text.bodySmall?.copyWith(color: t.colors.warning),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_step > 0)
          StarBridgeActionButton(
            controlKey: const Key('guide-listing-demo-back'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (_) => setState(() => _step--),
            child: Text(copy.text('tour.back')),
          ),
        if (last)
          StarBridgeActionButton(
            controlKey: const Key('guide-listing-demo-publish'),
            child: Text(copy.text('tour.demoPublish')),
          ),
        StarBridgeActionButton(
          controlKey: const Key('guide-listing-demo-next'),
          kind: StarBridgeActionKind.primary,
          onActivate: (source) => last
              ? dismissStarBridgeDialog(context, source: source)
              : setState(() => _step++),
          child: Text(copy.text(last ? 'tour.finishDemo' : 'tour.next')),
        ),
      ],
    );
  }
}

class _Sample extends StatelessWidget {
  const _Sample({required this.step, required this.copy});
  final int step;
  final GuideCopy copy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    Widget tile(String label, {bool on = false}) => Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaces.raised.fill,
          borderRadius: BorderRadius.circular(t.shape.radiusMedium),
          border: Border.all(
            color: on ? t.colors.accent : t.surfaces.raised.border,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(t.space.md),
          child: Text(label, style: text.bodyMedium),
        ),
      ),
    );
    Widget row(String a, String b) => Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xxs),
      child: Row(
        children: [
          Text(
            a,
            style: text.bodyMedium?.copyWith(color: t.colors.textSecondary),
          ),
          const Spacer(),
          Text(b, style: text.bodyMedium),
        ],
      ),
    );
    final gap = SizedBox(width: t.space.sm);
    return switch (step) {
      0 => Row(
        children: [
          tile(copy.text('tour.listing.sell'), on: true),
          gap,
          tile(copy.text('tour.listing.buy')),
          gap,
          tile(copy.text('tour.listing.barter')),
        ],
      ),
      1 => Row(
        children: [
          for (final n in ['A', 'B', 'C']) ...[
            tile('${copy.text('tour.listing.sampleItem')} $n', on: n == 'A'),
            if (n != 'C') gap,
          ],
        ],
      ),
      2 => Column(
        children: [
          row(copy.text('tour.listing.price'), '——'),
          row(copy.text('tour.listing.quantity'), '2'),
        ],
      ),
      _ => Column(
        children: [
          row(copy.text('tour.listing.step1'), copy.text('tour.listing.sell')),
          row(
            copy.text('tour.listing.step2'),
            '${copy.text('tour.listing.sampleItem')} A',
          ),
          row(copy.text('tour.listing.quantity'), '2'),
        ],
      ),
    };
  }
}

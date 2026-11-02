import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'onboarding_copy.dart';
import 'recognition_check_controller.dart';
import 'recognition_check_port.dart';

/// "确认识别正常": shows what the confirmed log slot currently sees.
class RecognitionCheckPanel extends StatelessWidget {
  const RecognitionCheckPanel({
    required this.copy,
    required this.controller,
    this.confirmedHandle,
    super.key,
  });
  final OnboardingCopy copy;
  final RecognitionCheckController controller;
  final String? confirmedHandle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: t.colors.textSecondary,
    );
    final view = controller.value;
    final s = view.snapshot;
    final locale = copy.locale;
    final (bannerKey, bannerColor) = !view.supported
        ? ('verify.banner.unsupported', t.colors.textSecondary)
        : s == null
        ? (
            view.error ? 'verify.banner.error' : 'verify.banner.loading',
            t.colors.textSecondary,
          )
        : s.ready
        ? ('verify.banner.ready', t.colors.success)
        : s.inactive
        ? ('verify.banner.inactive', t.colors.textSecondary)
        : s.listeningOff
        ? ('verify.banner.listeningOff', t.colors.warning)
        : s.state == 'otherSource'
        ? ('verify.banner.otherSource', t.colors.warning)
        : s.gameClosed
        ? ('verify.banner.notRunning', t.colors.textSecondary)
        : ('verify.banner.waiting', t.colors.textSecondary);
    final ready = s?.ready == true;
    final location = s?.location(locale.languageCode, locale.countryCode);
    final ship = s?.ship(locale.languageCode, locale.countryCode);
    final rows = <(String, String, bool)>[
      (
        'verify.row.game',
        ready
            ? copy
                  .text('verify.game.running')
                  .replaceAll('{version}', s!.version ?? '')
            : copy.text(
                s?.gameClosed == true
                    ? 'verify.game.closed'
                    : 'verify.game.unknown',
              ),
        ready,
      ),
      (
        'verify.row.identity',
        ready
            ? copy
                  .text('verify.identity.match')
                  .replaceAll('{handle}', s!.handle!)
            : copy
                  .text('verify.identity.waiting')
                  .replaceAll('{handle}', confirmedHandle ?? '—'),
        ready,
      ),
      (
        'verify.row.server',
        ready && s!.serverState == 'connected'
            ? s.serverRegion == null
                  ? copy.text('verify.server.connected')
                  : '${copy.text('verify.server.connected')} · ${s.serverRegion}'
            : copy.text(
                ready && s!.serverState == 'notConnected'
                    ? 'verify.server.notConnected'
                    : 'verify.server.unknown',
              ),
        ready && s!.serverState == 'connected',
      ),
      (
        'verify.row.location',
        ready && location != null
            ? location
            : copy.text('verify.location.unknown'),
        ready && location != null,
      ),
      (
        'verify.row.ship',
        ready && ship != null ? ship : copy.text('verify.ship.unknown'),
        ready && ship != null,
      ),
    ];
    return Container(
      key: const Key('recognition-check-panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surfaces.raised.fill,
        borderRadius: BorderRadius.circular(t.shape.radiusSmall),
        border: Border.all(color: t.surfaces.raised.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: Key('recognition-banner-${bannerKey.split('.').last}'),
            padding: EdgeInsets.all(t.space.md),
            color: bannerColor.withValues(alpha: .12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? '✓' : '◌',
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: bannerColor,
                  ),
                ),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.text('$bannerKey.title'),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(copy.text('$bannerKey.body'), style: small),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final (label, value, ok) in rows)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.space.md,
                vertical: t.space.sm,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: t.surfaces.raised.border),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      ok ? '✓' : '○',
                      style: TextStyle(
                        color: ok ? t.colors.success : t.colors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      copy.text(label),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(child: Text(value, style: small)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Short status for the progress line and the summary detail.
String recognitionStatusKey(RecognitionCheckView view) =>
    switch (view.outcome) {
      RecognitionCheckOutcome.passed => 'progress.verifyPassed',
      RecognitionCheckOutcome.skipped => 'progress.verifySkipped',
      RecognitionCheckOutcome.unavailable => 'progress.verifySkipped',
    };

bool recognitionReady(RecognitionCheckSnapshot? snapshot) =>
    snapshot?.ready == true;

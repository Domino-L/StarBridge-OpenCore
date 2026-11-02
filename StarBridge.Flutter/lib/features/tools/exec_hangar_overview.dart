import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'exec_hangar_port.dart';

String execHangarTime(DateTime value) {
  final d = value.toLocal();
  String two(int v) => '$v'.padLeft(2, '0');
  return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String execHangarCountdown(DateTime end, DateTime now) {
  final seconds = (end.difference(now).inMilliseconds / 1000).ceil().clamp(
    0,
    999999,
  );
  String two(int v) => '$v'.padLeft(2, '0');
  return '${two(seconds ~/ 3600)}:${two((seconds ~/ 60) % 60)}:${two(seconds % 60)}';
}

final class ExecHangarOverview extends StatelessWidget {
  const ExecHangarOverview({
    super.key,
    required this.phase,
    required this.nextChange,
    required this.now,
  });
  final ExecHangarPhase phase;
  final DateTime nextChange, now;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    String t(String key) => AppStrings.of(context).text('execHangar.$key');
    final leaving = phase.open && phase.green == 0 && phase.red == 0;
    final countdown = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${leaving
              ? t('closingSoon')
              : phase.open
              ? t('open')
              : t('closed')} · ${phase.open ? t('nextClose') : t('nextOpen')}',
          style: text.titleMedium?.copyWith(
            color: leaving ? tokens.colors.danger : null,
          ),
        ),
        if (leaving)
          Padding(
            padding: EdgeInsets.only(top: tokens.space.sm),
            child: Text(
              t('leaveNow'),
              key: const Key('exec-leave-warning'),
              style: text.bodyLarge?.copyWith(color: tokens.colors.danger),
            ),
          ),
        SizedBox(height: tokens.space.xs),
        Text(
          execHangarCountdown(nextChange, now),
          key: const Key('exec-countdown'),
          style: text.displaySmall?.copyWith(
            fontSize: tokens.typography.display * 1.35,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          execHangarTime(nextChange),
          style: text.bodyMedium?.copyWith(color: tokens.colors.textSecondary),
        ),
      ],
    );
    final lamps = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: tokens.space.lg,
          runSpacing: tokens.space.md,
          children: [
            for (var index = 0; index < 5; index++)
              Semantics(
                label:
                    '${t(['power', 'system', 'network', 'security', 'access'][index])} · ${t(index < phase.green
                        ? 'lampGreen'
                        : index < phase.green + phase.red
                        ? 'lampRed'
                        : 'lampOff')}',
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StandardIcon(
                        index < phase.green + phase.red
                            ? StandardIconSemantic.circle
                            : StandardIconSemantic.circleOutline,
                        size: 18,
                        color: index < phase.green
                            ? tokens.colors.success
                            : index < phase.green + phase.red
                            ? tokens.colors.danger
                            : tokens.colors.textDisabled,
                      ),
                      SizedBox(height: tokens.space.xs),
                      Text(
                        t(
                          [
                            'power',
                            'system',
                            'network',
                            'security',
                            'access',
                          ][index],
                        ),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: tokens.space.sm),
        Text(
          '${t('lightChange')} · ${execHangarCountdown(phase.end, now)}',
          style: text.bodySmall?.copyWith(color: tokens.colors.textSecondary),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              countdown,
              SizedBox(height: tokens.space.lg),
              lamps,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: countdown),
            SizedBox(width: tokens.space.xl),
            Expanded(child: lamps),
          ],
        );
      },
    );
  }
}

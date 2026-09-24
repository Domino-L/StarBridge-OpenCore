import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_models.dart';

/// Keeps official RSI identity and StarBridge-local authority visibly separate.
class OfficialFleetProfileIdentitySource extends StatelessWidget {
  const OfficialFleetProfileIdentitySource({
    required this.fleet,
    required this.observedAtUtc,
    super.key,
  });

  final OfficialFleetSummary fleet;
  final DateTime? observedAtUtc;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final rankName =
        fleet.officialRankName ?? strings.text('officialFleet.rank.unknown');
    final rankValue = fleet.officialRankValue;
    return StarBridgeSurface(
      key: const Key('official-fleet-profile-identity-source'),
      role: SurfaceRole.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = _SourceColumn(
            title: strings.text('officialFleet.profile.myIdentity'),
            color: tokens.domainColors.command.foreground,
            lines: [
              '$rankName · ${rankValue == null ? '—' : '$rankValue★'}',
              if (fleet.profile?.starBridgeRoleName case final role?)
                '${strings.text('officialFleet.profile.starBridgeRole')} · $role',
            ],
          );
          final source = _SourceColumn(
            title: strings.text('officialFleet.profile.syncSource'),
            color: tokens.domainColors.recon.foreground,
            lines: [
              strings.text('officialFleet.source'),
              if (observedAtUtc != null)
                '${strings.text('officialFleet.profile.observedAt')} · ${_formatObservedAt(context, observedAtUtc!)}',
            ],
          );
          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                SizedBox(height: tokens.space.lg),
                source,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identity),
              SizedBox(width: tokens.space.xl),
              Expanded(child: source),
            ],
          );
        },
      ),
    );
  }
}

class _SourceColumn extends StatelessWidget {
  const _SourceColumn({
    required this.title,
    required this.color,
    required this.lines,
  });

  final String title;
  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            borderRadius: tokens.shape.small,
          ),
        ),
        SizedBox(width: tokens.space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: tokens.space.xs),
              for (final line in lines)
                Padding(
                  padding: EdgeInsets.only(bottom: tokens.space.xxs),
                  child: Text(
                    line,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatObservedAt(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final date = MaterialLocalizations.of(context).formatCompactDate(local);
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date $time';
}

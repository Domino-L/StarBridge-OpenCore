import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Refresh feedback stays static so retained content does not animate or move.
class OfficialFleetRefreshNotice extends StatelessWidget {
  const OfficialFleetRefreshNotice({
    required this.active,
    this.refreshFailed = false,
    this.lastReadAtUtc,
    this.failureMessageKey = 'officialFleet.syncFailed',
    super.key,
  });
  final bool active;
  final bool refreshFailed;
  final DateTime? lastReadAtUtc;
  final String failureMessageKey;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final at = lastReadAtUtc?.toLocal();
    final labels = MaterialLocalizations.of(context);
    final message = active || !refreshFailed
        ? strings.text('officialFleet.refreshing')
        : at == null
        ? strings.text(failureMessageKey)
        : strings
              .text('${failureMessageKey}At')
              .replaceAll(
                '{time}',
                '${labels.formatShortDate(at)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
              );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: Visibility(
        visible: active || refreshFailed,
        maintainSize: true,
        maintainState: true,
        maintainAnimation: true,
        child: Semantics(
          liveRegion: true,
          child: Tooltip(
            message: message,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: context.tokens.space.xs),
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: context.tokens.colors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo.dart';
import 'community_chat_copy.dart';

/// The chat title. On organization (holo) surfaces it is bolder and spaced;
/// no English kicker (user 2026-10-29: no decorative English on chat).
class CommunityChatTitle extends StatelessWidget {
  const CommunityChatTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme;
    if (!OrganizationHolo.of(context)) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: title.titleLarge,
      );
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: title.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

/// Whether a message at [at] starts a new local day after [previous].
bool communityChatNewDay(DateTime? previous, DateTime at) {
  if (previous == null) return true;
  final a = previous.toLocal(), b = at.toLocal();
  return a.year != b.year || a.month != b.month || a.day != b.day;
}

/// Holo surfaces separate days with a centred date over a hairline.
class CommunityChatDayBreak extends StatelessWidget {
  const CommunityChatDayBreak(this.at, {super.key});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final local = at.toLocal(), now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final label = day == today
        ? communityChatText(context, 'today')
        : day == today.subtract(const Duration(days: 1))
        ? communityChatText(context, 'yesterday')
        : MaterialLocalizations.of(context).formatMediumDate(local);
    final line = Expanded(
      child: Divider(color: OrganizationHoloColors(context).hair, height: 1),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                letterSpacing: 2,
                color: context.tokens.colors.textDisabled,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

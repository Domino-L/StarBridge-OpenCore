import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

String rallyCount(AppStrings strings, String key, int count) =>
    strings.text(key).replaceAll('{count}', '$count');

String rallyCopy(AppStrings strings, String key) =>
    strings.text('officialFleet.rally.$key');

class RallyFieldLabel extends StatelessWidget {
  const RallyFieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: context.tokens.colors.textSecondary),
    ),
  );
}

class RallyChoice extends StatelessWidget {
  const RallyChoice({
    super.key,
    required this.order,
    required this.controlKey,
    required this.label,
    required this.selected,
    required this.onTap,
    this.pill = false,
  });

  final double order;
  final Key controlKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final height = pill
        ? tokens.density.compactControlHeight
        : tokens.density.controlHeight - 6;
    final border = selected
        ? colors.stateAccent
        : pill
        ? tokens.surfaces.panel.border
        : null;
    final side = border == null ? BorderSide.none : BorderSide(color: border);
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: Semantics(
        selected: selected,
        child: StarBridgeActionButton(
          controlKey: controlKey,
          kind: StarBridgeActionKind.quiet,
          minHeight: height,
          onActivate: (_) => onTap(),
          nativeStyle:
              TextButton.styleFrom(
                minimumSize: Size(0, height),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.symmetric(
                  horizontal: pill ? tokens.space.sm : tokens.space.xxs,
                  vertical: 4,
                ),
                backgroundColor: selected
                    ? (colors.accent == colors.stateAccent
                          ? tokens.surfaces.selected.fill
                          : colors.stateAccentSoft)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: pill ? tokens.shape.pill : tokens.shape.small,
                  side: side,
                ),
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? BorderSide(
                          color: colors.stateAccent,
                          width: tokens.stroke.focusWidth,
                        )
                      : side,
                ),
              ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected || pill
                  ? colors.textPrimary
                  : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class RallyColumns extends StatelessWidget {
  const RallyColumns({
    super.key,
    required this.wide,
    required this.gap,
    required this.first,
    required this.second,
    this.expandSecond = true,
  });

  final bool wide;
  final double gap;
  final Widget first;
  final Widget second;
  final bool expandSecond;

  @override
  Widget build(BuildContext context) => Flex(
    direction: wide ? Axis.horizontal : Axis.vertical,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: !wide
        ? CrossAxisAlignment.stretch
        : expandSecond
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center,
    children: [
      Flexible(flex: wide ? 1 : 0, fit: FlexFit.tight, child: first),
      SizedBox(width: wide ? gap : 0, height: wide ? 0 : 12),
      Flexible(
        flex: wide && expandSecond ? 1 : 0,
        fit: FlexFit.tight,
        child: second,
      ),
    ],
  );
}

class RallyPreview extends StatelessWidget {
  const RallyPreview({
    super.key,
    required this.message,
    required this.fleet,
    required this.displayName,
    required this.minutes,
  });

  final String message;
  final String? fleet;
  final String? displayName;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = tokens.colors;
    final muted = text.bodySmall?.copyWith(color: colors.textSecondary);
    final blank = message.isEmpty;
    final body = blank
        ? rallyCopy(strings, 'previewEmpty')
        : _quoteRallyPreview(message, strings.locale);
    final name = displayName?.trim();
    final fleetName = fleet?.trim();
    final title = fleetName == null || fleetName.isEmpty
        ? rallyCopy(strings, 'live')
        : rallyCopy(strings, 'titleBy').replaceAllMapped(
            RegExp(r'\{(fleet|name)\}'),
            (match) => match[1] == 'fleet'
                ? fleetName
                : name == null || name.isEmpty
                ? rallyCopy(strings, 'previewYou')
                : name,
          );
    final timeLeft = rallyCount(strings, 'officialFleet.rally.left', minutes);

    return Semantics(
      key: const Key('official-fleet-rally-preview'),
      container: true,
      excludeSemantics: true,
      label: rallyCopy(
        strings,
        'previewSemantics',
      ).replaceFirst('{text}', body),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: tokens.surfaces.panel.fill,
            borderRadius: tokens.shape.medium,
            border: Border.all(color: tokens.surfaces.status.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rallyCopy(strings, 'preview'), style: muted),
              const SizedBox(height: 8),
              Builder(
                builder: (context) => RallyColumns(
                  // Panel padding 14 + 14 and a 1-px border on each side.
                  wide:
                      rallyDialogContentWidth(context) - 30 >= 360 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 18,
                  gap: 12,
                  expandSecond: false,
                  first: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.warning,
                          borderRadius: tokens.shape.pill,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              body,
                              key: const Key(
                                'official-fleet-rally-preview-body',
                              ),
                              style: text.bodyMedium?.copyWith(
                                color: blank
                                    ? colors.textDisabled
                                    : colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text('$title · $timeLeft', style: muted),
                          ],
                        ),
                      ),
                    ],
                  ),
                  second: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _previewAction(context, 'coming', primary: true),
                      _previewAction(context, 'cannot', primary: false),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewAction(
    BuildContext context,
    String label, {
    required bool primary,
  }) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final style = primary
        ? theme.filledButtonTheme.style
        : theme.outlinedButtonTheme.style;
    final shape =
        style?.shape?.resolve({}) ??
        RoundedRectangleBorder(borderRadius: tokens.shape.small);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: primary
            ? tokens.colors.stateAccent
            : tokens.surfaces.floating.fill,
        shape: shape.copyWith(
          side: primary
              ? BorderSide.none
              : BorderSide(color: tokens.surfaces.panel.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          rallyCopy(AppStrings.of(context), label),
          style: theme.textTheme.labelMedium?.copyWith(
            color: primary
                ? (tokens.isDark
                      ? tokens.surfaces.floating.fill
                      : tokens.surfaces.raised.fill)
                : tokens.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

String _quoteRallyPreview(String message, Locale locale) {
  if (message.length >= 2 &&
      ((message.startsWith('「') && message.endsWith('」')) ||
          (message.startsWith('“') && message.endsWith('”')))) {
    return message;
  }
  return locale.languageCode == 'zh' ? '「$message」' : '“$message”';
}

class RallyAudience extends StatelessWidget {
  const RallyAudience({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final parts = rallyCopy(strings, 'onlineNow').split('{count}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RallyFieldLabel(rallyCopy(strings, 'target')),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: tokens.density.controlHeight),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              key: const Key('official-fleet-rally-target'),
              semanticsLabel: rallyCount(
                strings,
                'officialFleet.rally.targetValue',
                count,
              ),
              style: text.bodySmall,
              TextSpan(
                children: [
                  TextSpan(text: parts.first),
                  TextSpan(
                    text: '$count',
                    style: text.titleMedium?.copyWith(
                      fontFamily: 'Rajdhani',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: parts.last),
                  TextSpan(
                    text: ' · ${rallyCopy(strings, 'laterOnline')}',
                    style: TextStyle(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RallyQuota extends StatelessWidget {
  const RallyQuota({super.key, required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colors.textSecondary);
    final usedUp = remaining == 0;
    final parts = rallyCopy(strings, 'quota').split('{count}');
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: parts.first),
              TextSpan(
                text: '$remaining',
                style: TextStyle(
                  color: usedUp ? colors.danger : colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: parts.last),
            ],
          ),
          key: const Key('official-fleet-rally-quota'),
          semanticsLabel: rallyCount(
            strings,
            'officialFleet.rally.rules',
            remaining,
          ),
          style: muted,
        ),
        ExcludeSemantics(
          child: Row(
            key: const Key('official-fleet-rally-quota-dots'),
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              for (var i = 0; i < 3; ++i)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < remaining
                        ? colors.stateAccent
                        : tokens.surfaces.status.border,
                  ),
                ),
            ],
          ),
        ),
        ExcludeSemantics(
          excluding: !usedUp,
          child: Text(
            rallyCopy(strings, usedUp ? 'quotaUsedUp' : 'oneAtATime'),
            style: usedUp ? muted?.copyWith(color: colors.danger) : muted,
          ),
        ),
      ],
    );
  }
}

/// Width the rally dialog content gets: 588 at most, otherwise the window minus the
/// default dialog insets (40 + 40) and content padding (24 + 24). AlertDialog asks for
/// intrinsic sizes, so the dialog decides narrow layouts from this instead of LayoutBuilder.
double rallyDialogContentWidth(BuildContext context) {
  final available = MediaQuery.sizeOf(context).width - 128;
  return available < 0 ? 0 : (available > 588 ? 588 : available);
}

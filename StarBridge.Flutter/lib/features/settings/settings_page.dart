import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/feature_registry.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'help_support_settings_page.dart';
import 'settings_capability_overview.dart';
import 'settings_feature.dart';
import 'settings_models.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.initialSection,
    required this.accountAndIdentityBuilder,
    required this.generalDataBuilder,
    required this.syncPrivacyBuilder,
    required this.notificationsBuilder,
    this.confirmPrivacyLeave,
    this.confirmNotificationsLeave,
    this.diagnosticsBuilder,
    this.helpSupportBuilder,
    super.key,
  });

  final SettingsSection initialSection;
  final SettingsContentBuilder accountAndIdentityBuilder;
  final SettingsContentBuilder generalDataBuilder;
  final SettingsContentBuilder syncPrivacyBuilder;
  final SettingsContentBuilder notificationsBuilder;
  final SettingsContentBuilder? diagnosticsBuilder;
  final SettingsContentBuilder? helpSupportBuilder;
  final DestinationLeaveGuard? confirmPrivacyLeave;
  final DestinationLeaveGuard? confirmNotificationsLeave;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsSection _selected;
  bool _selecting = false;
  final _pickerKey = GlobalKey<FormFieldState<SettingsSection>>();

  Future<void> _select(SettingsSection section) async {
    if (_selecting || section == _selected) return;
    _selecting = true;
    try {
      if (_selected == SettingsSection.notifications &&
          widget.confirmNotificationsLeave != null &&
          !await widget.confirmNotificationsLeave!(context)) {
        return;
      }
      if (!mounted) return;
      if (_selected == SettingsSection.syncPrivacy &&
          widget.confirmPrivacyLeave != null &&
          !await widget.confirmPrivacyLeave!(context)) {
        return;
      }
      if (mounted) setState(() => _selected = section);
    } finally {
      _selecting = false;
      if (mounted) _pickerKey.currentState?.didChange(_selected);
    }
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  tokens.space.lg,
                  tokens.space.md,
                  tokens.space.lg,
                  0,
                ),
                child: KeyedSubtree(
                  key: const Key('settings-section-picker'),
                  child: DropdownButtonFormField<SettingsSection>(
                    key: _pickerKey,
                    initialValue: _selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context)
                          .text('settings.sectionPicker'),
                    ),
                    items: [
                      for (final section in visibleSettingsSections)
                        DropdownMenuItem(
                          value: section,
                          child: Text(
                            AppStrings.of(context).text(section.labelKey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _select(value);
                      }
                    },
                  ),
                ),
              ),
              Expanded(child: _content()),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth < 960 ? 196 : 276,
              child: _SettingsRail(
                selected: _selected,
                compact: constraints.maxWidth < 960,
                onSelect: _select,
              ),
            ),
            VerticalDivider(width: tokens.stroke.hairline),
            Expanded(child: _content()),
          ],
        );
      },
    );
  }

  Widget _content() {
    if (_selected == SettingsSection.accountIdentity) {
      return widget.accountAndIdentityBuilder(context);
    }
    if (_selected == SettingsSection.generalData) {
      return widget.generalDataBuilder(context);
    }
    if (_selected == SettingsSection.syncPrivacy) {
      return widget.syncPrivacyBuilder(context);
    }
    if (_selected == SettingsSection.notifications) {
      return widget.notificationsBuilder(context);
    }
    if (_selected == SettingsSection.aboutLegal) {
      return widget.helpSupportBuilder?.call(context) ??
          const HelpSupportSettingsPage();
    }
    if (_selected == SettingsSection.diagnostics &&
        widget.diagnosticsBuilder != null) {
      return widget.diagnosticsBuilder!(context);
    }
    return _DeferredSettingsOverview(section: _selected);
  }
}

class _SettingsRail extends StatelessWidget {
  const _SettingsRail({
    required this.selected,
    required this.onSelect,
    required this.compact,
  });

  final SettingsSection selected;
  final bool compact;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return ColoredBox(
      color: tokens.surfaces.navigation.fill,
      child: ListView(
        padding: EdgeInsets.all(tokens.space.md),
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: tokens.space.sm,
              bottom: tokens.space.sm,
            ),
            child: Text(
              strings.text('settings.sections.title'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          for (final section in visibleSettingsSections)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.space.xs),
              child: _SettingsRailItem(
                section: section,
                selected: selected == section,
                compact: compact,
                onPressed: () => onSelect(section),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsRailItem extends StatelessWidget {
  const _SettingsRailItem({
    required this.section,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final SettingsSection section;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Material(
      color: selected
          ? tokens.surfaces.selected.fill
          : tokens.surfaces.navigation.fill,
      borderRadius: tokens.shape.small,
      child: InkWell(
        key: Key('settings-section-${section.name}'),
        onTap: onPressed,
        borderRadius: tokens.shape.small,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.sm,
            vertical: tokens.space.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarBridgeIcon(
                section.icon,
                size: tokens.icons.medium,
                color: selected
                    ? tokens.colors.accent
                    : tokens.colors.textSecondary,
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text(section.labelKey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? tokens.colors.accent
                            : tokens.colors.textPrimary,
                      ),
                    ),
                    if (!compact) ...[
                      SizedBox(height: tokens.space.xxs),
                      Text(
                        strings.text(section.descriptionKey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeferredSettingsOverview extends StatelessWidget {
  const _DeferredSettingsOverview({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SingleChildScrollView(
      key: Key('settings-deferred-${section.name}'),
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        tokens.space.xxl,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text(section.labelKey),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                strings.text(section.descriptionKey),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              SizedBox(height: tokens.space.lg),
              PlannedSettingsCapabilities(section: section),
            ],
          ),
        ),
      ),
    );
  }
}

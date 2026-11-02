import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../settings/local_privacy_controller.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// Main-fleet sharing defaults on the fleet page (user decision 2026-10-29,
/// replacing the 10-28 confirm dialog): a member who never chose shares
/// everything with their main fleet; a member whose main fleet changed keeps
/// their earlier choice for the new one ("换完舰队默认继承之前的共享设置",
/// "如果一直没有设置默认全部共享"). Either is saved through the ordinary
/// official save and announced once, with the way to change it in Settings.
///
/// It never blocks the page and never withholds: while the state is loading,
/// cannot be read, has unsaved edits elsewhere, or the save fails, the page
/// shows as usual and the next entry or refresh tries again. Invisibility and
/// paused sharing still take priority. An earlier star limit this Host cannot
/// keep is not applied here (see `fleetChanged`); Settings asks instead.
class OfficialFleetFirstSharingChoice extends StatefulWidget {
  const OfficialFleetFirstSharingChoice({
    required this.controller,
    required this.sourceRef,
    required this.child,
    super.key,
  });

  final LocalPrivacyController controller;
  final String sourceRef;
  final Widget child;

  @override
  State<OfficialFleetFirstSharingChoice> createState() =>
      _OfficialFleetFirstSharingChoiceState();

  /// Rereads the member's own main fleet and sharing state, as a fresh entry
  /// does; used by the fleet page's refresh button. Never while sharing
  /// settings hold unsaved edits: a failed read would drop that draft.
  /// True when it applied a default and announced it.
  static Future<bool> recheck(BuildContext context) async {
    final state = context
        .findAncestorStateOfType<_OfficialFleetFirstSharingChoiceState>();
    if (state == null || state.widget.controller.dirty) return false;
    return state._read();
  }
}

class _OfficialFleetFirstSharingChoiceState
    extends State<OfficialFleetFirstSharingChoice> {
  bool _applying = false, _entered = false;

  /// The context a default was last tried for; a read that was already in
  /// flight at entry is evaluated once more when it settles.
  Object? _tried;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_settled);
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_settled);
    super.dispose();
  }

  Object? get _context =>
      (widget.controller.scopeEpoch, widget.controller.officialScope?.scopeRef);

  void _settled() {
    if (!_entered || _applying || _tried == _context) return;
    unawaited(_applyDefault());
  }

  Future<bool> _read() async {
    if (!mounted || _applying) return false;
    _entered = true;
    _tried = null;
    // Do not reset another editor's ordinary or official draft on entry.
    final owner = widget.controller;
    if ((owner.status == LocalPrivacyStatus.initial ||
            owner.status == LocalPrivacyStatus.unavailable) &&
        !owner.dirty) {
      await owner.refresh();
    } else if (owner.needsReload && !owner.dirty) {
      await owner.refresh(silently: true);
    } else {
      await owner.refreshOfficialRuntimePrivacy();
    }
    return mounted && await _applyDefault();
  }

  Future<bool> _applyDefault() async {
    final owner = widget.controller;
    final scope = owner.officialScope;
    // Still reading: [_settled] evaluates again once the read settles.
    if (owner.officialScopeReading) return false;
    _tried = _context;
    if (!owner.officialRuntimePrivacySupported ||
        owner.status != LocalPrivacyStatus.ready ||
        owner.needsReload ||
        owner.officialScopeFailed ||
        owner.dirty ||
        scope == null ||
        scope.state != 'available' ||
        scope.sourceRef != widget.sourceRef ||
        !(scope.choiceRequired || scope.fleetChanged)) {
      return false;
    }
    final inherited = scope.fleetChanged;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final strings = AppStrings.of(context);
    _applying = true;
    try {
      final saved = await owner.confirmOfficialFirstChoice(
        inherited ? scope.savedFields : 15,
        audience: inherited ? scope.maximumRankValue : null,
      );
      if (!saved || !mounted) return false;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          starBridgeTimedSnackBar(
            key: const Key('official-fleet-sharing-default-applied'),
            content: Text(
              strings.text(
                inherited
                    ? 'privacy.official.inheritedApplied'
                    : 'privacy.official.defaultApplied',
              ),
            ),
          ),
        );
      return true;
    } finally {
      _applying = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final owner = widget.controller;
      final scope = owner.officialScope;
      if (owner.officialRuntimePrivacySupported &&
          owner.status == LocalPrivacyStatus.ready &&
          !owner.needsReload &&
          !owner.officialScopeFailed &&
          scope?.state == 'available' &&
          scope?.sourceRef == widget.sourceRef &&
          owner.publicationView.errorCode ==
              'privacy_publication.existing_scope_confirmation_required') {
        return Column(
          children: [
            Text(
              AppStrings.of(context).text('privacy.official.savedNeedsReview'),
            ),
            Expanded(child: widget.child),
          ],
        );
      }
      return widget.child;
    },
  );
}

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../common/organization_holo.dart';
import '../common/organization_holo_art.dart';
import '../common/organization_holo_deck.dart';
import '../common/organization_workspace_frame.dart';
import 'official_fleet_backdrop.dart';
import 'official_fleet_holo_header.dart';
import 'official_fleet_holo_paint.dart';
import 'official_fleet_models.dart';
import 'official_fleet_screen_switch.dart';
import 'official_fleet_wheel_gate.dart';
import 'official_fleet_section_rail.dart';
import 'official_fleet_workspace_header.dart';

/// The main fleet's two-screen holo shell for any organization (user
/// decision 2026-10-23: "组织页面应该和主舰队用同一套外观 上下部分这样").
///
/// Upper screen: the holo header over the section rail (tiles on tall
/// screens). Lower screen: the slim bar (with the tabs on wide windows) over
/// the glass work surface. The wheel or a touchpad swipe moves between them
/// as on the main fleet; choosing a rail entry enters that section.
class OrganizationHoloShell extends StatefulWidget {
  const OrganizationHoloShell({
    required this.deck,
    required this.railItems,
    required this.section,
    required this.onSection,
    required this.tabs,
    required this.body,
    this.backdrop,
    this.actions,
    this.enterLabel,
    this.upperExtra,
    super.key,
  });

  /// Shown on the upper screen between the header and the rail (a
  /// community's online, activity and contact facts: never hidden).
  final Widget? upperExtra;

  final OrganizationHoloDeck deck;

  /// Page art behind both screens (a community uses its banner).
  final OrganizationHoloArt? backdrop;
  final List<OfficialFleetRailItem> railItems;

  /// The section the lower screen shows; the rail marks it as last visited.
  final OfficialFleetWorkspaceSection section;
  final ValueChanged<OfficialFleetWorkspaceSection> onSection;

  /// Section tabs: in the bar on wide windows, otherwise in the surface.
  final Widget tabs;

  /// The lower screen's surface content. [tabsInBar] tells the body to leave
  /// its own tab row out.
  final Widget Function(BuildContext context, {required bool tabsInBar}) body;

  /// Organization commands next to the rail and in the bar.
  final Widget? actions;
  final String? enterLabel;

  @override
  State<OrganizationHoloShell> createState() => _OrganizationHoloShellState();
}

class _OrganizationHoloShellState extends State<OrganizationHoloShell> {
  bool _lower = false, _entryPlayed = false, _bodyAtTop = true;
  double _pan = 0;
  final _wheel = OfficialFleetWheelGate();

  void _enter(OfficialFleetWorkspaceSection section) {
    setState(() {
      _lower = true;
      _bodyAtTop = true;
    });
    if (section != widget.section) widget.onSection(section);
  }

  void _onWheel(double dy) {
    if (dy > 0 && !_lower) {
      _enter(widget.section);
    } else if (dy < 0 && _lower && _wheel.up(-dy, bodyAtTop: _bodyAtTop)) {
      setState(() => _lower = false);
    }
  }

  bool _onBodyScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) _wheel.bodyMoved();
    // Visual top: reversed lists (chat) start at their newest end.
    _bodyAtTop =
        (metrics.axisDirection == AxisDirection.up
            ? metrics.extentAfter
            : metrics.extentBefore) <=
        0;
    return false;
  }

  Widget _toggle(BuildContext context, bool lower) {
    final strings = AppStrings.of(context);
    return StarBridgeIconAction(
      controlKey: Key(
        lower ? 'organization-holo-expand' : 'organization-holo-collapse',
      ),
      label: strings.text(
        lower
            ? 'officialFleet.workspace.expand'
            : 'officialFleet.workspace.collapse',
      ),
      onActivate: (_) =>
          lower ? setState(() => _lower = false) : _enter(widget.section),
      icon: StandardIcon(
        lower
            ? StandardIconSemantic.unfoldMore
            : StandardIconSemantic.unfoldLess,
        size: 18,
      ),
    );
  }

  Widget _trailing(BuildContext context, bool lower) => OrganizationHoloFace(
    outsideSurface: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [?widget.actions, _toggle(context, lower)],
    ),
  );

  @override
  Widget build(BuildContext context) => OfficialFleetBackdrop(
    art: widget.backdrop,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 700;
        final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
        final railCompact =
            constraints.maxWidth < OfficialFleetSectionRail.compactBelow;
        // No command row here: the banner gets that height on top.
        final topChrome =
            (180 +
                (widget.upperExtra == null ? 0 : 120) +
                // The facts row under the name slab (community, 2026-10-29).
                (widget.deck.readouts.isEmpty ? 0 : 56) +
                (stacked ? 56 : 0) +
                (railCompact ? OfficialFleetSectionRail.compactExtra : 0)) *
            scale;
        final maxBanner = math.max(
          110.0,
          math.min(
            constraints.maxWidth / 3,
            constraints.maxHeight - topChrome - 150 * scale,
          ),
        );
        final tiles =
            !railCompact && maxBanner >= constraints.maxWidth / 3 - .5;
        final barTabs = !stacked && constraints.maxWidth >= 1100 * scale;
        final entry = _lower || _entryPlayed
            ? OfficialFleetHoloEntry.none
            : OfficialFleetHoloEntry.quick;
        if (!_lower) _entryPlayed = true;
        double headerMax(bool lower) => math.max(
          64.0,
          lower
              ? constraints.maxHeight - (stacked ? 56 : 0) * scale - 200 * scale
              : constraints.maxHeight,
        );
        Widget header(bool lower) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: headerMax(lower)),
          child: UnconstrainedBox(
            constrainedAxis: Axis.horizontal,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: lower
                ? OfficialFleetHoloBar(
                    deck: widget.deck,
                    tabs: barTabs ? widget.tabs : null,
                    trailing: barTabs ? _trailing(context, true) : null,
                  )
                : OfficialFleetHoloHeader(
                    deck: widget.deck,
                    maxBannerHeight: maxBanner,
                    entry: entry,
                  ),
          ),
        );
        final rail = OfficialFleetSectionRail(
          enterLabel:
              widget.enterLabel ??
              AppStrings.of(context).text('officialFleet.rail.enter'),
          lastVisited: widget.section,
          trailing: _trailing(context, false),
          compact: railCompact,
          onSelected: _enter,
          items: widget.railItems,
        );
        Widget screen(bool lower) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (lower || tiles)
              header(lower)
            else
              Flexible(child: header(lower)),
            if (!lower && widget.upperExtra != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: widget.upperExtra,
              ),
            if (stacked && lower)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _trailing(context, true),
                ),
              ),
            if (lower)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, stacked ? 4 : 12, 20, 20),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onBodyScroll,
                    child: OrganizationWorkspaceSurface(
                      child: widget.body(context, tabsInBar: barTabs),
                    ),
                  ),
                ),
              )
            else if (tiles)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: rail,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: rail,
              ),
          ],
        );
        return Listener(
          // Blank parts of a screen hit-test through to the backdrop;
          // the wheel still belongs to the switch (2026-10-24).
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _onWheel(event.scrollDelta.dy);
          },
          onPointerPanZoomUpdate: (event) {
            _pan += event.panDelta.dy;
            if (_pan.abs() < 24) return;
            _onWheel(-_pan);
            _pan = 0;
          },
          onPointerPanZoomEnd: (_) => _pan = 0,
          child: OfficialFleetScreenSwitch(
            lower: _lower,
            upper: (_) => screen(false),
            lowerBuilder: (_) => screen(true),
            banner: widget.deck.banner,
            bannerHeight: math.min(maxBanner, constraints.maxWidth / 3),
            barHeight: 64 * scale,
          ),
        );
      },
    ),
  );
}

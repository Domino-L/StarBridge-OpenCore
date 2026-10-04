import 'package:flutter/material.dart';

import '../communities/community_section_navigation.dart';

/// Shared client/menu geometry. Stable pane subtrees preserve chat drafts when
/// crossing the breakpoint rather than replacing Row with Column.
class RoomWorkspaceLayout extends StatefulWidget {
  const RoomWorkspaceLayout({
    super.key,
    required this.members,
    required this.chat,
    this.compactTabs = false,
  });
  final Widget members, chat;
  final bool compactTabs;
  @override
  State<RoomWorkspaceLayout> createState() => _RoomWorkspaceLayoutState();
}

class _RoomWorkspaceLayoutState extends State<RoomWorkspaceLayout> {
  String _selected = 'members';
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (widget.compactTabs) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final split =
            box.maxWidth >= 850 * scale && box.maxHeight >= 420 * scale;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!split)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: CommunitySectionNavigation(
                  sections: const {'members': true, 'chat': true},
                  selected: _selected,
                  onSelected: (value) => setState(() => _selected = value),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, body) => Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: split ? (body.maxWidth - 12) * .6 : body.maxWidth,
                      child: _pane(
                        !split && _selected != 'members',
                        widget.members,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: split ? (body.maxWidth - 12) * .4 : body.maxWidth,
                      child: _pane(!split && _selected != 'chat', widget.chat),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      final wide = box.maxWidth >= 850;
      return Flex(
        direction: wide ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: wide ? 3 : 1, child: widget.members),
          const SizedBox(width: 12, height: 12),
          Expanded(flex: wide ? 2 : 1, child: widget.chat),
        ],
      );
    },
  );
  Widget _pane(bool hidden, Widget child) => Offstage(
    offstage: hidden,
    child: TickerMode(
      enabled: !hidden,
      child: ExcludeFocus(excluding: hidden, child: child),
    ),
  );
}

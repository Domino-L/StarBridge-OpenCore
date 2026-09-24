import 'package:flutter/widgets.dart';

/// Lazily retain visited sections only within one authorized workspace.
/// Hidden sections have no focus, animation, read receipts or polling ticks.
class CommunitySectionStack extends StatefulWidget {
  const CommunitySectionStack({
    required this.selected,
    required this.sections,
    super.key,
  });
  final String selected;
  final Map<String, WidgetBuilder> sections;

  @override
  State<CommunitySectionStack> createState() => _CommunitySectionStackState();
}

class _CommunitySectionStackState extends State<CommunitySectionStack> {
  final visited = <String>{};

  @override
  Widget build(BuildContext context) {
    visited.retainAll(widget.sections.keys);
    visited.add(widget.selected);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in widget.sections.entries)
          if (visited.contains(entry.key))
            Offstage(
              key: ValueKey(entry.key),
              offstage: entry.key != widget.selected,
              child: TickerMode(
                enabled: entry.key == widget.selected,
                child: ExcludeFocus(
                  excluding: entry.key != widget.selected,
                  child: Builder(builder: entry.value),
                ),
              ),
            ),
      ],
    );
  }
}

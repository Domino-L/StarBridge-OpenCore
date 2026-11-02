import 'package:flutter/widgets.dart';

/// Lazily retain visited sections within one authorized organization. Callers
/// key the stack by their authorized context; hidden sections cannot focus,
/// animate or run visibility-bound polling/read receipts.
class OrganizationSectionStack extends StatefulWidget {
  const OrganizationSectionStack({
    required this.selected,
    required this.sections,
    super.key,
  });
  final String selected;
  final Map<String, WidgetBuilder> sections;

  @override
  State<OrganizationSectionStack> createState() =>
      _OrganizationSectionStackState();
}

class _OrganizationSectionStackState extends State<OrganizationSectionStack> {
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

import 'package:flutter/widgets.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import 'friends_module.dart';

/// Reports the actual visible directory, not the completion of remote sync.
final class FriendsLoadingContent extends StatelessWidget {
  const FriendsLoadingContent(this.module, {required this.child, super.key});
  final FriendsModule module;
  final Widget child;
  @override
  Widget build(BuildContext context) => LoadingContentProbe(
    route: '/friends',
    status: switch (module.state) {
      FriendsReadState.loading => LoadingContentStatus.waiting,
      FriendsReadState.ready when module.displayOnly =>
        LoadingContentStatus.partial,
      FriendsReadState.ready when module.rows.isEmpty =>
        LoadingContentStatus.empty,
      FriendsReadState.ready when module.refreshFailed =>
        LoadingContentStatus.partial,
      FriendsReadState.ready => LoadingContentStatus.data,
      _ => LoadingContentStatus.unavailable,
    },
    items: module.rows.length,
    child: child,
  );
}

/// A route may name a part of its destination with `?section=` (a
/// notification opening 我的交易 or 交易消息): the feature route, and the
/// section the feature is asked to show.
(String, String?) destinationSection(String route) {
  final uri = Uri.tryParse(route);
  final section = uri?.queryParameters['section'];
  return section == null || uri == null ? (route, null) : (uri.path, section);
}

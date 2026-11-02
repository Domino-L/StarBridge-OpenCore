import '../account/account_models.dart';

/// Receipt for a complete authenticated domain read, never an RPC context.
final class LocalHangarReadScope {
  const LocalHangarReadScope({required this.generation, required this.route});
  final int generation;
  final AccountRoute route;
  bool matches(AccountDisplayHandoff proof) =>
      generation == proof.generation && proof.matchesRoute(route);
}

abstract interface class LocalHangarReadScopeSource {
  LocalHangarReadScope? get readScope;
}

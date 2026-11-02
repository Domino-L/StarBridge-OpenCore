/// The parent of every SCM category this client has read, so an item filed
/// under a sub-category still draws its root category's icon (items without a
/// photo, user 2026-10-23). Categories are public and the same for everyone.
final _parents = <int, int>{};

void marketRememberCategories(Iterable<Map<String, Object?>> rows) {
  for (final row in rows) {
    final id = (row['id'] as num?)?.toInt();
    if (id != null) _parents[id] = (row['parentId'] as num?)?.toInt() ?? 0;
  }
}

/// The root (1–9 on SCM) above [category]. Without the tree yet, SCM's
/// numbering still points at it: sub-categories carry their root's digits
/// first (31, 311 → 3).
int marketRootCategory(int category) {
  var current = category;
  for (var hop = 0; hop < 8; hop++) {
    final parent = _parents[current];
    if (parent == null || parent <= 0) break;
    current = parent;
  }
  if (_parents.containsKey(current) && (_parents[current] ?? 0) <= 0) {
    return current;
  }
  while (current >= 10) {
    current ~/= 10;
  }
  return current;
}

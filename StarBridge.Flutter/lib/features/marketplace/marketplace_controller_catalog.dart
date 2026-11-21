import 'marketplace_controller.dart';

extension MarketplaceCatalog on MarketplaceController {
  Future<void> refreshCatalog() async {
    await Future.wait([
      load(
        'catalog',
        relation.isEmpty ? 'search' : relation,
        id: relatedId,
        query: keyword,
        category: categoryId ?? 0,
      ),
      // A catalog restored from the saved view has not read its item yet.
      if (relation.isNotEmpty &&
          relatedId > 0 &&
          blocks['recent:$relatedId'] == null &&
          !loading.contains('recent:$relatedId'))
        load('recent:$relatedId', 'item', id: relatedId),
    ]);
  }

}

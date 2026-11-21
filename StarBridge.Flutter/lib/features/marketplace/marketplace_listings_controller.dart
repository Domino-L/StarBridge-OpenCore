import 'dart:async';

import 'package:flutter/widgets.dart';

import 'marketplace_category_roots.dart';
import 'marketplace_details.dart' show marketMyOrders;
import 'marketplace_port.dart';
import 'marketplace_numbers.dart';
import 'marketplace_recovery.dart';
import 'marketplace_quality.dart';
import 'marketplace_order_full.dart';

/// Listing UI contract; SCM request translation belongs to the Host.
abstract interface class MarketplaceListingsPort {
  Future<MarketRow> read();
  Future<void> write(String operation, MarketRow input);
}

abstract interface class MarketplaceListingLookup {
  /// One SCM search page (20 rows); [page] starts at 1.
  Future<List<MarketRow>> searchItems(String query, {int category = 0, int page = 1});
  Future<List<MarketRow>> categories();
  Future<MarketRow> nextPage(int page);
}

class ListingDraft {
  ListingDraft({
    this.item = const {},
    this.side = 'sell',
    this.price = '',
    this.quantity = '1',
    this.days = 7,
    this.visible = true,
    this.location = '',
    this.quality = '',
    this.wanted = '',
    this.wantedQuantity = '1',
    this.offeredQuantity = '1',
    this.wantedItem = const {},
    this.manifestId,
  });
  MarketRow item, wantedItem;
  String offeredQuantity;
  String side, price, quantity, location, quality, wanted, wantedQuantity;
  int days;
  bool visible;
  Object? manifestId;
  // Accept the grouped prices shown in the prototype without accepting malformed groups.
  num? get amount {
    final text = price.trim();
    if (text.contains(',') &&
        !RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(text)) {
      return null;
    }
    final value = num.tryParse(text.replaceAll(',', ''));
    return value != null && value.isFinite ? value : null;
  }

  String? get validation {
    if (item['id'] == null && manifestId == null) return '请选择物品';
    final count = int.tryParse(quantity);
    if (count == null || count < 1 || count > 999999) return '数量须为 1～999999';
    final amount = this.amount;
    if (manifestId == null && side != 'barter') {
      if (amount == null ||
          !amount.isFinite ||
          amount <= 0 ||
          amount > 1000000000000000) {
        return '单价须为 0～10¹⁵ UEC';
      }
    }
    if (side == 'barter' &&
        ((int.tryParse(wanted) ?? 0) <= 0 || wanted == '${item['id']}')) {
      return '请选择想要的物品';
    }
    if (side == 'barter' && ((int.tryParse(offeredQuantity) ?? 0) < 1 ||
        (int.tryParse(offeredQuantity) ?? 0) > 999 ||
        (int.tryParse(wantedQuantity) ?? 0) < 1 ||
        (int.tryParse(wantedQuantity) ?? 0) > 999)) {
      return '每次数量须为 1～999';
    }
    if (quality.isNotEmpty && (int.tryParse(quality) == null || int.parse(quality) < 0 || int.parse(quality) > 1000)) {
      return '品质须为 0～1000';
    }
    if (location.trim().isEmpty) return '请选择交易地点';
    if (![0, 7, 14].contains(days)) return '请选择有效期';
    return null;
  }

  MarketRow toInput() => {
    'itemId': item['id'],
    'side': side,
    'quantity': int.parse(quantity),
    if (manifestId == null && side != 'barter' && price.isNotEmpty) 'price': amount,
    'expiryDays': days,
    'visible': visible,
    'location': location,
    if (quality.isNotEmpty) 'quality': quality,
    if (side == 'barter') 'offeredQuantity': int.parse(offeredQuantity),
    if (side == 'barter') 'wanted': [{'itemId': int.parse(wanted), 'quantity': int.parse(wantedQuantity)}],
    if (manifestId != null) 'manifestId': manifestId,
  };
}

class MarketplaceListingsController extends ChangeNotifier {
  MarketplaceListingsController(this.port);
  final MarketplaceListingsPort port;
  MarketOrderFull? fullOrders;
  Future<void> Function(BuildContext, MarketRow)? openOrder;
  Future<void> Function(BuildContext)? login;
  Future<void> Function()? onChanged;
  num? Function(int, int)? bestPrice;
  Future<void> Function(Iterable<(int, int)>)? ensureBestPrices;
  int? get activeSingleListingCount => marketListingCount(rows, total);
  bool get capacityFull => marketListingFull(rows, total, limit);

  num? listingBestPrice(MarketRow row) {
    if (!marketSingleListing(row)) return null;
    // The hall's live best price; a row that carries its own `best` (the
    // Host does not send one today) is used only when the hall is absent.
    final read = bestPrice;
    if (read == null) return marketNumber(row['best']);
    final id = marketNumber(row['itemId'])?.toInt();
    return id == null ? null : read(id, row['side'] == 'buy' ? 0 : 1);
  }

  Future<void> ensureListingPrices(List<MarketRow> listings) async {
    final read = ensureBestPrices;
    if (read == null) return;
    final wanted = [for (final row in listings)
      if (marketSingleListing(row) && marketNumber(row['itemId']) != null)
        (marketNumber(row['itemId'])!.toInt(), row['side'] == 'buy' ? 0 : 1)];
    for (var i = 0; i < wanted.length; i += 10) {
      await read(wanted.skip(i).take(10));
      if (_disposed) return;
    }
    if (!_disposed) notifyListeners();
  }

  /// The hall's live tier reads, so a quality listing is priced against its
  /// own tier (set by the publish entry; absent elsewhere).
  MarketQualityTiersStore? qualityTiers;

  void ensureTiers(int itemId) {
    final store = qualityTiers;
    if (store == null || !store.stale(itemId)) {
      return;
    }
    unawaited(
      store.ensure(itemId).whenComplete(() {
        if (!_disposed) notifyListeners();
      }),
    );
  }
  List<MarketRow> rows = [], items = [], manifests = [], locations = [];
  /// SCM item categories for browsing in the publish wizard; [itemCategory] 0 means all.
  List<MarketRow> categories = [];
  int itemCategory = 0;
  /// Whether the current item search may have another page.
  bool itemsMore = false, itemsLoading = false;
  String _itemQuery = '';
  int _itemPage = 1;
  int? limit;
  int? total;
  int _page = 1, _searchVersion = 0;
  bool loadingMore = false, _draining = false;
  int _readRevision = 0;
  bool get allListingsLoaded => total != null && rows.length >= total!;
  String? tradeWindow, error;
  MarketRow? tradeProfile;
  void applyTradeProfile(MarketRow profile, String window) {
    tradeProfile = profile;
    limit = marketNumber(profile['orderLimit'])?.toInt();
    tradeWindow = window;
    notifyListeners();
  }
  bool loading = false, pending = false, writeUncertain = false;
  String? errorCode;
  bool _disposed = false;
  bool _uncertainReadBack = false;
  Future<void> inspectUncertainWrite() async {
    if (loading || pending || _disposed) return;
    await refresh();
    confirmReadBack();
  }
  void confirmReadBack() {
    if (!_uncertainReadBack || loading || pending || _disposed) return;
    writeUncertain = false;
    _uncertainReadBack = false;
    error = null;
    errorCode = null;
    notifyListeners();
  }
  Future<void> refresh() async {
    if (loading || _disposed) return;
    loading = true;
    _readRevision++;
    _uncertainReadBack = false;
    error = null;
    notifyListeners();
    try {
      final result = await port.read();
      if (_disposed) return;
      rows = marketRows(result['rows']);
      marketMyOrders.addAll(rows.map((r) => '${r['id']}'));
      total = result['total'] as int?;
      _page = 1;
      unawaited(ensureListingPrices(rows));
      // Once the user has searched or browsed a category, that answer owns
      // the item list; a base read finishing later must not replace it.
      if (_searchVersion == 0) {
        items = marketRows(result['items']);
        itemsMore = items.length >= 20;
      }
      manifests = marketRows(result['manifests']);
      locations = marketRows(result['locations']);
      limit = result['limit'] as int?;
      tradeWindow = result['tradeWindow'] as String?;
      tradeProfile = result['tradeProfile'] is Map ? Map<String, Object?>.from(result['tradeProfile'] as Map) : null;
      errorCode = null;
      if (writeUncertain) {
        _uncertainReadBack = true;
        error = '请核对挂单是否已改变，确认后再继续操作';
      }
    } on Object catch (e) {
      if (!_disposed) {
        errorCode = e is MarketplaceTradeError ? e.code : null;
        error = '暂时读不到挂单，请重试';
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
    if (!_disposed && error == null) await loadRemaining();
  }

  /// Read at most ten pages, even if a filter leaves no scrollable rows.
  Future<void> loadRemaining() async {
    if (_draining || loading || _disposed) return;
    _draining = true;
    try {
      while (!_disposed && !loading && !loadingMore && _page < 10 &&
          total != null && rows.length < total!) {
        final page = _page;
        await loadMore();
        if (_page == page) break;
      }
    } finally {
      _draining = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadCategories() async {
    final source = port;
    if (source is! MarketplaceListingLookup || categories.isNotEmpty) return;
    try {
      final found = await (source as MarketplaceListingLookup).categories();
      if (_disposed) return;
      categories = found;
      marketRememberCategories(found);
      notifyListeners();
    } on Object { /* Browsing is optional; search still works. */ }
  }

  Future<void> searchItems(String query, {int? category}) async {
    final source = port;
    if (source is! MarketplaceListingLookup) return;
    if (category != null) {
      itemCategory = category;
      notifyListeners();
    }
    final version = ++_searchVersion;
    _itemQuery = query;
    _itemPage = 1;
    itemsLoading = true;
    notifyListeners();
    try {
      final found = await (source as MarketplaceListingLookup)
          .searchItems(query, category: itemCategory);
      if (_disposed || version != _searchVersion) return;
      items = found;
      itemsMore = found.length >= 20;
    } on Object { /* Preserve current suggestions on a failed search. */ }
    finally {
      if (!_disposed && version == _searchVersion) {
        itemsLoading = false;
        notifyListeners();
      }
    }
  }

  /// Next page of the current item search, appended without duplicates.
  Future<void> searchMoreItems() async {
    final source = port;
    if (source is! MarketplaceListingLookup || !itemsMore || itemsLoading || _disposed) return;
    final version = _searchVersion;
    itemsLoading = true;
    notifyListeners();
    try {
      final found = await (source as MarketplaceListingLookup)
          .searchItems(_itemQuery, category: itemCategory, page: _itemPage + 1);
      if (_disposed || version != _searchVersion) return;
      _itemPage++;
      items = {for (final row in [...items, ...found]) row['id']: row}.values.toList();
      itemsMore = found.length >= 20;
    } on Object { /* Keep what is shown; the next scroll retries. */ }
    finally {
      if (!_disposed && version == _searchVersion) {
        itemsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    final source = port;
    if (source is! MarketplaceListingLookup || loading || loadingMore || _disposed ||
        _page >= 10 || total == null || rows.length >= total!) {
      return;
    }
    loadingMore = true;
    final revision = _readRevision;
    notifyListeners();
    try {
      final next = await (source as MarketplaceListingLookup).nextPage(_page + 1);
      if (_disposed || revision != _readRevision) return;
      rows = {for (final row in [...rows, ...marketRows(next['rows'])]) row['id']: row}.values.toList();
      marketMyOrders.addAll(rows.map((r) => '${r['id']}'));
      total = next['total'] as int?;
      _page++;
      unawaited(ensureListingPrices(rows));
      notifyListeners();
    } on Object { if (!_disposed && revision == _readRevision) error = '暂时读不到挂单，请重试'; }
    finally {
      loadingMore = false;
      if (!_disposed) {
        notifyListeners();
        if (revision != _readRevision) {
          unawaited(Future<void>(() => loadRemaining()));
        }
      }
    }
  }

  Future<bool> write(String operation, MarketRow input) async {
    if (pending || _disposed || writeUncertain) return false;
    pending = true;
    error = null;
    notifyListeners();
    try {
      await port.write(operation, input);
      if (_disposed) return false;
      await refresh();
      if (!_disposed) await onChanged?.call();
      return true;
    } on Object catch (e) {
      if (!_disposed) {
        errorCode = marketplaceFailureCode(e);
        writeUncertain = !listingDefiniteRejection(errorCode!);
        error = '操作未确认，请刷新挂单后核对';
      }
      return false;
    } finally {
      if (!_disposed) {
        pending = false;
        notifyListeners();
      }
    }
  }

  Future<List<MarketRow>> setVisibility(
    List<MarketRow> selected,
    bool visible,
  ) async {
    if (pending || _disposed || writeUncertain) return [];
    pending = true;
    notifyListeners();
    final results = <MarketRow>[];
    String? failureCode;
    // SCM visibility-batch affects a whole side, never use it for arbitrary selection.
    try {
      for (final row in selected) {
        if (_disposed) break;
        try {
          await port.write('visibility', {'id': row['id'], 'visible': visible});
          results.add({'name': row['name'], 'success': true, 'state': 'ok'});
        } on Object catch (e) {
          errorCode = marketplaceFailureCode(e);
          failureCode = errorCode;
          final definite = listingDefiniteRejection(errorCode!);
          // Each row says what happened to it: refused, unconfirmed, or never
          // sent after an unconfirmed one (CX-HALL-FIX2-REVIEW P2).
          results.add({'name': row['name'], 'success': false,
              'state': definite ? 'rejected' : 'uncertain', 'code': errorCode});
          if (!definite) {
            writeUncertain = true;
            error = '操作未确认，请刷新挂单后核对';
            for (final unattempted in selected.skip(results.length)) {
              results.add({'name': unattempted['name'], 'success': false,
                  'state': 'skipped'});
            }
            break;
          }
        }
      }
      if (!_disposed) await refresh();
      if (!_disposed && results.any((r) => r['success'] == true)) await onChanged?.call();
      if (!_disposed && failureCode != null) {
        errorCode = failureCode;
        error = '操作未确认，请刷新挂单后核对';
      }
    } finally {
      if (!_disposed) {
        pending = false;
        notifyListeners();
      }
    }
    return results;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

bool listingDefiniteRejection(String code) => const {
  ...marketplacePreflightFailures,
  'marketplace.sign_in_required', 'marketplace.forbidden', 'marketplace.busy',
  'marketplace.account_unbound', 'marketplace.trade_time_required',
  'marketplace.contact_required', 'marketplace.account_abnormal', 'marketplace.account_banned',
  'marketplace.listing_limit', 'marketplace.listing_same_item_limit',
  'marketplace.listing_manifest_limit', 'marketplace.listing_item_invalid',
  'marketplace.listing_invalid', 'marketplace.listing_has_ongoing',
  'marketplace.listing_cannot_publish', 'marketplace.listing_quantity_below_ongoing',
  'marketplace.checklist_invalid', 'marketplace.template_limit', 'marketplace.template_system',
  'marketplace.not_owner', 'marketplace.listing_rejected',
  'marketplace.trade_rejected',
}.contains(code);

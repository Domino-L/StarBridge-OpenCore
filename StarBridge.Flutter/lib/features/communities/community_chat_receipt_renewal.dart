import 'community_chat_controller.dart';

final _renewed = Expando<bool>();

extension CommunityChatReceiptRenewal on CommunityChatController {
  /// True when a read just renewed the references and the report should run
  /// again. Once per lapse: if it is refused after that, the notice stays.
  Future<bool> renewLapsedReceipt() async {
    if (receiptError != 'refreshRequired') {
      if (receiptError == null) _renewed[this] = null;
      return false;
    }
    if (_renewed[this] == true || loading) return false;
    _renewed[this] = true;
    final read = await refresh(silent: true);
    return read != null;
  }
}

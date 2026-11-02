import 'account_port.dart';

/// Optional phased reads. Preparation is scheduled by the existing app idle
/// owner; neither this contract nor a display cache grants authorization.
abstract interface class AccountReadPreparationPort {
  bool get supportsStagedReads;
  bool get hasPendingReadPreparation;
  bool get shouldRetryReadPreparation;
  Future<AccountPortResult?> prepareNextRead({bool retry = false});
  void cancelReadPreparation();
}

abstract interface class AccountReadPreparation {
  bool get supportsPreparedReads;
  Future<bool> prepareNextRead();
  void cancelReadPreparation();
}

import 'community_ownership_transfer_port.dart';
export 'community_ownership_transfer_port.dart'
    show CommunityOwnershipTransferOutcome;

abstract interface class CommunityOwnershipExitPort {
  Stream<void> get invalidations;
  bool get ownershipExitAvailable;
  Future<CommunityOwnershipExit> readOwnershipExit({
    String? targetRef,
    String? memberRef,
    String? editRef,
  });
  Future<CommunityOwnershipTransferOutcome> leaveWithSuccessor(
    String requestId,
    String editRef, {
    bool confirmUncertainRetry = false,
  });
}

/// An explicit departure confirmation, never a retaining-transfer preview.
final class CommunityOwnershipExit {
  CommunityOwnershipExit.example(this.successor) {
    if (!successor.leaveAfterTransfer) throw const FormatException();
  }
  final CommunityOwnershipTransfer successor;
  String get targetRef => successor.targetRef;
  String get memberRef => successor.memberRef;
  String get editRef => successor.editRef;
  bool get canLeave => successor.canTransfer;
  factory CommunityOwnershipExit.parse(Map<String, Object?> value) =>
      CommunityOwnershipExit.example(
        CommunityOwnershipTransfer.parse(
          value,
          expectedLeaveAfterTransfer: true,
        ),
      );
}

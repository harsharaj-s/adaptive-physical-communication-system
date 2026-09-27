import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/manager/transfer_state_machine.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

void main() {
  test('transfer state machine valid flow', () {
    final sm = TransferStateMachine();
    expect(sm.state, TransferState.idle);

    sm.transition(TransferState.discovering);
    sm.transition(TransferState.testingChannels);
    sm.transition(TransferState.negotiating);
    sm.transition(TransferState.transferring);
    sm.transition(TransferState.degraded);
    sm.transition(TransferState.switchingChannel);
    sm.transition(TransferState.recovering);
    sm.transition(TransferState.transferring);
    sm.transition(TransferState.completed);

    expect(sm.state, TransferState.completed);
    expect(sm.history.length, 9);
  });

  test('rejects invalid transition', () {
    final sm = TransferStateMachine();
    expect(() => sm.transition(TransferState.transferring), throwsStateError);
  });
}

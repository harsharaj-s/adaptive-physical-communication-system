import 'package:adaptive_physical_communication/core/types/types.dart';

class TransferStateMachine {
  TransferState _state = TransferState.idle;
  final List<({TransferState from, TransferState to, int timestamp})> _history =
      [];

  static const _validTransitions = {
    TransferState.idle: [TransferState.discovering, TransferState.failed],
    TransferState.discovering: [TransferState.testingChannels, TransferState.failed],
    TransferState.testingChannels: [TransferState.negotiating, TransferState.failed],
    TransferState.negotiating: [TransferState.transferring, TransferState.failed],
    TransferState.transferring: [
      TransferState.degraded,
      TransferState.completed,
      TransferState.failed,
    ],
    TransferState.degraded: [
      TransferState.switchingChannel,
      TransferState.recovering,
      TransferState.transferring,
      TransferState.failed,
    ],
    TransferState.switchingChannel: [
      TransferState.recovering,
      TransferState.transferring,
      TransferState.failed,
    ],
    TransferState.recovering: [TransferState.transferring, TransferState.failed],
    TransferState.completed: [TransferState.idle],
    TransferState.failed: [TransferState.idle],
  };

  TransferState get state => _state;

  bool canTransition(TransferState to) =>
      _validTransitions[_state]?.contains(to) ?? false;

  void transition(TransferState to) {
    if (!canTransition(to)) {
      throw StateError('Invalid state transition: $_state → $to');
    }
    _history.add((
      from: _state,
      to: to,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _state = to;
  }

  void forceState(TransferState to) {
    _history.add((
      from: _state,
      to: to,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _state = to;
  }

  void reset() {
    _state = TransferState.idle;
    _history.clear();
  }

  List<({TransferState from, TransferState to, int timestamp})> get history =>
      List.unmodifiable(_history);
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:adaptive_physical_communication/core/channels/hardware_channels.dart';
import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/logging/structured_logger.dart';
import 'package:adaptive_physical_communication/core/media/gallery_saver.dart';
import 'package:adaptive_physical_communication/core/media/image_compress.dart';
import 'package:adaptive_physical_communication/core/manager/transfer_manager.dart';
import 'package:adaptive_physical_communication/core/performance/performance_comparator.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_modem.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/fountain/fountain_qr_modem.dart';
import 'package:adaptive_physical_communication/core/physical/hardware_phy_config.dart';
import 'package:adaptive_physical_communication/core/physical/optical_modem.dart';
import 'package:adaptive_physical_communication/core/physical/optical_tx_profile.dart';
import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/core/protocol/packet_codec.dart';
import 'package:adaptive_physical_communication/core/simulation/scenarios.dart' as sim;
import 'package:adaptive_physical_communication/core/simulation/simulation_orchestrator.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';
import 'package:adaptive_physical_communication/core/platform/vibration_transmitter_state.dart';
import 'package:adaptive_physical_communication/ui/models/compose_payload.dart';

export 'package:adaptive_physical_communication/core/channels/hardware_channels.dart';

/// Unified application controller — simulation, hardware, and performance modes.
class AppController extends ChangeNotifier {
  final StructuredLogger logger = StructuredLogger();
  AppController() {
    onOpticalTransmitCancel = requestCancelTransfer;
  }

  OperationMode _mode = OperationMode.simulation;
  EndpointRole _role = EndpointRole.sender;
  TransferMode _transferMode = TransferMode.broadcast;
  String _scenarioId = 'optical-degrades';
  bool _running = false;

  DashboardSnapshot? _senderSnapshot;
  DashboardSnapshot? _receiverSnapshot;
  SimulationResult? _lastSimResult;
  List<StrategyResult> _comparisonResults = [];
  final List<LogEntry> _liveLogs = [];
  final List<ChatMessage> _chatMessages = [];
  Uint8List? _lastReceivedData;
  String _statusMessage = 'Ready';
  bool _lastTransferSucceeded = false;
  DateTime? _lastIncomingAt;
  Timer? _hardwareListenTimer;
  final Map<int, Uint8List> _incomingPacketBuffer = {};
  int? _incomingExpectedPackets;
  int? _incomingTransferId;
  final Set<int> _deliveredTransferIds = {};
  Timer? _incomingIdleTimer;
  int _incomingBufferedCount = 0;
  bool _cancelRequested = false;
  CommChannelId? _selectedPhysicalChannel;

  OperationMode get mode => _mode;
  EndpointRole get role => _role;
  TransferMode get transferMode => _transferMode;
  String get scenarioId => _scenarioId;
  bool get running => _running;
  DashboardSnapshot? get senderSnapshot => _senderSnapshot;
  DashboardSnapshot? get receiverSnapshot => _receiverSnapshot;
  SimulationResult? get lastSimResult => _lastSimResult;
  List<StrategyResult> get comparisonResults => _comparisonResults;
  List<LogEntry> get liveLogs => _liveLogs;
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  Uint8List? get lastReceivedData => _lastReceivedData;
  String get statusMessage => _statusMessage;
  bool get lastTransferSucceeded => _lastTransferSucceeded;
  DateTime? get lastIncomingAt => _lastIncomingAt;
  int get incomingMessageCount =>
      _chatMessages.where((m) => !m.isOutgoing).length;
  List<sim.ScenarioDefinition> get availableScenarios => sim.scenarios;
  bool get hardwareAvailable => isPhysicalChannelSupported;

  HardwareOpticalChannel? _opticalChannel;
  HardwareAcousticChannel? _acousticChannel;
  HardwareVibrationChannel? _vibrationChannel;
  bool _hardwareChannelsActive = false;

  HardwareOpticalChannel? get opticalChannel => _opticalChannel;
  HardwareAcousticChannel? get acousticChannel => _acousticChannel;
  HardwareVibrationChannel? get vibrationChannel => _vibrationChannel;
  bool get hardwareChannelsActive => _hardwareChannelsActive;
  bool get cameraActive => _opticalChannel?.isCameraStreaming ?? false;
  CommChannelId? get selectedPhysicalChannel => _selectedPhysicalChannel;
  bool get cancelRequested => _cancelRequested;

  /// Configure hardware flow for send or receive on a specific physical channel.
  Future<void> configurePhysicalFlow({
    required EndpointRole role,
    required CommChannelId channel,
  }) async {
    _mode = OperationMode.hardware;
    _role = role;
    _selectedPhysicalChannel = channel;
    _transferMode = channel == CommChannelId.vibration
        ? TransferMode.unicast
        : TransferMode.broadcast;
    _statusMessage = role == EndpointRole.sender
        ? 'Ready to send via ${channelIdToName(channel)}'
        : 'Listening on ${channelIdToName(channel)}';
    notifyListeners();
    if (role == EndpointRole.receiver) {
      await startHardwareChannels(forRole: EndpointRole.receiver);
    }
  }

  void requestCancelTransfer() {
    _cancelRequested = true;
    opticalTransmitterState.setTransmitting(false);
    vibrationTransmitterState.setTransmitting(false);
    notifyListeners();
  }

  void resetCancelFlag() {
    _cancelRequested = false;
  }

  /// Send composed content over the selected physical channel.
  Future<bool> sendPhysicalMessage({
    required ComposePayload payload,
    required CommChannelId channel,
  }) async {
    if (_running || payload.isEmpty) return false;

    resetCancelFlag();
    await configurePhysicalFlow(role: EndpointRole.sender, channel: channel);

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _chatMessages.add(ChatMessage(
      id: id,
      isOutgoing: true,
      type: payload.type,
      status: ChatMessageStatus.sending,
      timestamp: DateTime.now(),
      text: payload.text,
      data: payload.type == ChatMessageType.text || payload.type == ChatMessageType.link
          ? null
          : payload.data,
      fileName: payload.fileName,
      mimeType: payload.mimeType,
      byteSize: payload.byteSize,
    ));
    notifyListeners();

    try {
      final envelope = await _prepareEnvelope(payload);
      if (channel == CommChannelId.optical &&
          envelope.length > FountainQrModem.maxEnvelopeBytes) {
        _statusMessage =
            'Payload too large for Light fountain QR '
            '(${envelope.length} B, max ${FountainQrModem.maxEnvelopeBytes} B).';
        _markChatMessage(id, ChatMessageStatus.failed);
        notifyListeners();
        return false;
      }

      // Fast direct path for Light and Sound broadcast (no protocol
      // fragmentation). The sound limit depends on which modem is active, so
      // ask the channel rather than assume the legacy one.
      final acousticLimit =
          _acousticChannel?.maxEnvelopeBytes ?? hardwareAcousticDirectMaxBytes;
      if (channel == CommChannelId.optical ||
          (channel == CommChannelId.acoustic &&
              envelope.length <= acousticLimit)) {
        final ok = await _sendDirectEnvelope(envelope, channel);
        // Light has no return path: the sender only knows it streamed.
        _markChatMessage(
          id,
          !ok
              ? ChatMessageStatus.failed
              : channel == CommChannelId.optical
                  ? ChatMessageStatus.sent
                  : ChatMessageStatus.delivered,
        );
        return ok;
      }

      await runHardwareTransfer(envelope, forcedChannel: channel);
      if (_lastTransferSucceeded) {
        _markChatMessage(id, ChatMessageStatus.delivered);
        return true;
      }
      _markChatMessage(id, ChatMessageStatus.failed);
      return false;
    } catch (_) {
      _markChatMessage(id, ChatMessageStatus.failed);
      return false;
    }
  }

  Future<Uint8List> _prepareEnvelope(ComposePayload payload) async {
    if (payload.type == ChatMessageType.image) {
      final compressed = await compressImageForTransfer(payload.data);
      return ChatPayloadCodec.encode(
        type: ChatMessageType.image,
        data: compressed,
        fileName: payload.fileName ?? 'photo.jpg',
        mimeType: 'image/jpeg',
      );
    }
    return payload.toEnvelope();
  }

  Future<bool> _sendDirectEnvelope(
    Uint8List envelope,
    CommChannelId channel,
  ) async {
    if (_running) return false;
    _running = true;
    _lastTransferSucceeded = false;
    _statusMessage = 'Transmitting via ${channelIdToName(channel)}…';
    notifyListeners();

    try {
      await startHardwareChannels(forRole: EndpointRole.sender);
      if (_cancelRequested) return false;

      switch (channel) {
        case CommChannelId.optical:
          await _opticalChannel!.transmitEnvelope(envelope);
        case CommChannelId.acoustic:
          await _acousticChannel!.transmitEnvelope(envelope);
        case CommChannelId.vibration:
          return false;
      }

      _lastTransferSucceeded = true;
      _statusMessage = channel == CommChannelId.optical
          ? _opticalStreamSummary(envelope.length)
          : 'Sent ${envelope.length} bytes via ${channelIdToName(channel)}';
      return true;
    } catch (e) {
      logger.error('Direct send failed: $e');
      _statusMessage = 'Send failed — ${e.toString().split('\n').first}';
      return false;
    } finally {
      _running = false;
      opticalTransmitterState.setTransmitting(false);
      final outcome = _statusMessage;
      await _restoreHardwareAfterTransfer();
      // Restarting the channels resets the status to "Ready to send"; the
      // sender screen needs to show how the transfer actually ended.
      _statusMessage = outcome;
      notifyListeners();
    }
  }

  String _opticalStreamSummary(int bytes) {
    final modem = _opticalChannel?.fountainModem;
    if (modem == null) return 'Streamed $bytes bytes via Light';
    final secs = modem.lastTxDuration.inSeconds;
    final shown = '${modem.lastTxFrames} QR frames in ${secs}s';
    return modem.lastTxEnd == FountainTxEnd.safetyCap
        ? 'Paused after the ${FountainQrModem.maxStreamDuration.inMinutes}-'
            'minute safety limit ($shown). If the receiver does not show '
            'DONE, tap Resume — it keeps what it already collected.'
        : 'Streaming stopped ($shown). If the receiver shows DONE, the '
            'file arrived; otherwise tap Resume — it keeps its progress.';
  }

  Future<void> _restoreHardwareAfterTransfer() async {
    if (_mode != OperationMode.hardware || _selectedPhysicalChannel == null) {
      return;
    }
    await startHardwareChannels(forRole: _role);
  }

  /// Start listening for incoming messages on the given channel.
  Future<void> startListening(CommChannelId channel) async {
    resetCancelFlag();
    await configurePhysicalFlow(role: EndpointRole.receiver, channel: channel);
  }

  Future<void> stopListening() async {
    await stopHardwareChannels();
    _selectedPhysicalChannel = null;
    _statusMessage = 'Stopped listening';
    notifyListeners();
  }

  ChatMessage? get latestIncomingMessage {
    for (var i = _chatMessages.length - 1; i >= 0; i--) {
      if (!_chatMessages[i].isOutgoing) return _chatMessages[i];
    }
    return null;
  }

  /// Packets received so far for the in-progress transfer (0 if idle).
  int get incomingBufferedPacketCount => _incomingBufferedCount;

  /// Expected total packets for the in-progress transfer (null if unknown).
  int? get incomingExpectedPacketCount => _incomingExpectedPackets;

  /// Fountain / CSK progress on optical RX (received, expected).
  (int received, int total)? get opticalQrChunkProgress =>
      _opticalChannel?.chunkProgress;

  /// Live optical transfer metrics for HUD.
  OpticalTransferMetrics get opticalTransferMetrics =>
      _opticalChannel?.activeModem.metrics ?? OpticalTransferMetrics.empty;

  OpticalMetricsNotifier? get opticalMetricsNotifier =>
      _opticalChannel?.metricsNotifier;

  OpticalTxProfile _opticalTxProfile = OpticalTxProfile.auto;
  OpticalTxProfile get opticalTxProfile => _opticalTxProfile;

  void setOpticalTxProfile(OpticalTxProfile profile) {
    _opticalTxProfile = profile;
    _opticalChannel?.setTxProfile(profile);
    notifyListeners();
  }

  AcousticTxProfile _acousticTxProfile = AcousticTxProfile.standard;
  AcousticTxProfile get acousticTxProfile => _acousticTxProfile;

  void setAcousticTxProfile(AcousticTxProfile profile) {
    _acousticTxProfile = profile;
    _acousticChannel?.txProfile = profile;
    notifyListeners();
  }

  /// Rough seconds to play a payload at the current sound settings.
  int acousticEtaSeconds(int bytes) {
    final k = math.max(1, (bytes / _acousticTxProfile.blockLen).ceil());
    return (AcousticFountainModem.expectedSymbols(k) *
            _acousticTxProfile.frameSeconds())
        .ceil();
  }

  /// Stop a sound transmission that is still playing.
  void cancelAcousticTransmit() => _acousticChannel?.cancelTransmit();

  /// True when the acoustic mic capture stream is running.
  bool get acousticMicActive => _acousticChannel?.micStreaming ?? false;

  /// Re-request mic permission and restart listening (Sound receive).
  Future<void> retryAcousticListening() async {
    if (_selectedPhysicalChannel != CommChannelId.acoustic) return;
    await _acousticChannel?.initialize();
    await startHardwareChannels(forRole: EndpointRole.receiver);
  }

  /// Clear receive arming state so the next transfer can be accepted/displayed.
  void prepareForNextMessage() {
    _incomingPacketBuffer.clear();
    _incomingExpectedPackets = null;
    _incomingTransferId = null;
    _incomingBufferedCount = 0;
    _incomingIdleTimer?.cancel();
    _incomingIdleTimer = null;
    if (_deliveredTransferIds.length > 32) {
      final keep = _deliveredTransferIds.toList().reversed.take(16).toSet();
      _deliveredTransferIds
        ..clear()
        ..addAll(keep);
    }
    _resetPhysicalReceiveCaches(resetDedup: true);
    unawaited(_opticalChannel?.ensureReceiverStreaming());
    _statusMessage = _selectedPhysicalChannel != null
        ? 'Listening on ${channelIdToName(_selectedPhysicalChannel!)} — ready for next'
        : 'Ready for next message';
    notifyListeners();
  }

  void _resetPhysicalReceiveCaches({bool resetDedup = false}) {
    _opticalChannel?.clearReceiveCaches(resetDedup: resetDedup);
    _acousticChannel?.clearReceiveCaches(resetDedup: resetDedup);
    _vibrationChannel?.clearReceiveCaches();
  }

  void setMode(OperationMode m) {
    if (_mode == m) return;
    _mode = m;
    _statusMessage = m == OperationMode.hardware
        ? (_transferMode == TransferMode.broadcast
            ? 'Live broadcast — one sender, many receivers'
            : 'Live hardware mode — pair with another device')
        : 'Simulation mode — test on this device';
    notifyListeners();
    if (m == OperationMode.hardware && !_running) {
      unawaited(startHardwareChannels());
    }
  }

  void setTransferMode(TransferMode mode) {
    if (_transferMode == mode) return;
    _transferMode = mode;
    if (_mode == OperationMode.hardware) {
      _statusMessage = mode == TransferMode.broadcast
          ? 'Broadcast mode — one sender can reach many receivers'
          : 'Unicast mode — paired 1:1 with one receiver';
    }
    notifyListeners();
  }

  void setRole(EndpointRole r) {
    if (_role == r) return;
    _role = r;
    _statusMessage = r == EndpointRole.sender
        ? (_transferMode == TransferMode.broadcast
            ? 'Sender — broadcast to all nearby receivers (QR or tones)'
            : 'Sender — point screen at receiver camera, keep phones close')
        : (_transferMode == TransferMode.broadcast
            ? 'Receiver — listening for broadcast from any sender'
            : 'Receiver — point camera at sender screen, tap Start if needed');
    notifyListeners();
    if (_mode == OperationMode.hardware && !_running) {
      unawaited(startHardwareChannels());
    }
  }

  void setScenario(String id) {
    _scenarioId = id;
    notifyListeners();
  }

  void clearLogs() {
    _liveLogs.clear();
    logger.clear();
    notifyListeners();
  }

  void clearChat() {
    _chatMessages.clear();
    notifyListeners();
  }

  void _markChatMessage(String id, ChatMessageStatus status) {
    final i = _chatMessages.indexWhere((m) => m.id == id);
    if (i >= 0) {
      _chatMessages[i] = _chatMessages[i].copyWith(status: status);
      notifyListeners();
    }
  }

  Future<void> _autoSaveToGallery(ChatMessage msg) async {
    final saved = await GallerySaver.instance.save(msg);
    final what = msg.type == ChatMessageType.image ? 'Photo' : 'Video';
    _statusMessage = saved
        ? '$what saved to Gallery (${GallerySaver.albumName})'
        : '$what received — ${GallerySaver.instance.errorFor(msg.id) ?? 'not saved'}';
    notifyListeners();
  }

  void _addIncomingChat(Uint8List raw) {
    final msg = ChatPayloadCodec.decodeIncoming(raw, isOutgoing: false);
    if (msg != null) {
      _chatMessages.add(msg);
      _lastIncomingAt = DateTime.now();
      _statusMessage = switch (msg.type) {
        ChatMessageType.image =>
          'Photo received (${msg.byteSize ?? 0} bytes) — displaying',
        ChatMessageType.video =>
          'Video received (${msg.byteSize ?? 0} bytes) — playing',
        ChatMessageType.file =>
          'File received (${msg.fileName ?? 'file'}, ${msg.byteSize ?? 0} bytes)',
        _ => 'Message received via physical channel',
      };
      notifyListeners();
      if (GallerySaver.canSave(msg) && GallerySaver.instance.isSupported) {
        unawaited(_autoSaveToGallery(msg));
      }
      return;
    }
    if (ChatPayloadCodec.isApcmEnvelope(raw)) {
      _statusMessage =
          'Incomplete image/message (${raw.length} B) — hold camera steady until all QR frames scan';
      notifyListeners();
    }
  }

  /// Send text, image, video, or file to the paired device.
  Future<void> sendChat({
    required ChatMessageType type,
    required Uint8List payload,
    String? text,
    String? fileName,
    String? mimeType,
  }) async {
    if (_running) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _chatMessages.add(ChatMessage(
      id: id,
      isOutgoing: true,
      type: type,
      status: ChatMessageStatus.sending,
      timestamp: DateTime.now(),
      text: text,
      data: type == ChatMessageType.text ? null : payload,
      fileName: fileName,
      mimeType: mimeType,
      byteSize: payload.length,
    ));
    notifyListeners();

    final envelope = type == ChatMessageType.text && text != null
        ? ChatPayloadCodec.encodeText(text)
        : ChatPayloadCodec.encode(
            type: type,
            data: payload,
            fileName: fileName,
            mimeType: mimeType,
          );

    try {
      if (_mode == OperationMode.simulation) {
        await runSimulation(data: envelope);
        if (_lastSimResult?.dataMatch == true) {
          _markChatMessage(id, ChatMessageStatus.delivered);
          final rx = ChatPayloadCodec.decodeIncoming(envelope, isOutgoing: false);
          if (rx != null) _chatMessages.add(rx.copyWith(id: '${id}_rx'));
        } else {
          _markChatMessage(id, ChatMessageStatus.failed);
        }
      } else {
        await runHardwareTransfer(envelope);
        if (_lastTransferSucceeded) {
          _markChatMessage(id, ChatMessageStatus.delivered);
        } else {
          _markChatMessage(id, ChatMessageStatus.failed);
        }
      }
    } catch (_) {
      _markChatMessage(id, ChatMessageStatus.failed);
    }
  }

  Future<void> sendChatText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await sendChat(
      type: ChatMessageType.text,
      payload: Uint8List.fromList(trimmed.codeUnits),
      text: trimmed,
    );
  }

  Future<void> _ensureChannelInitialized(
    CommChannelId channelId, {
    bool setupOpticalCamera = false,
  }) async {
    if (!isPhysicalChannelSupported) {
      throw StateError('Physical channels require a phone or Chrome browser');
    }
    switch (channelId) {
      case CommChannelId.optical:
        _opticalChannel ??= HardwareOpticalChannel(
          logger: logger,
          profile: _opticalTxProfile,
        );
        _opticalChannel!.setTxProfile(_opticalTxProfile);
        await _opticalChannel!.initialize(setupCamera: setupOpticalCamera);
      case CommChannelId.acoustic:
        _acousticChannel ??= HardwareAcousticChannel(logger: logger);
        _acousticChannel!.txProfile = _acousticTxProfile;
        await _acousticChannel!.initialize();
      case CommChannelId.vibration:
        if (isVibrationSupported) {
          _vibrationChannel ??= HardwareVibrationChannel(logger: logger);
          await _vibrationChannel!.initialize();
        }
    }
  }

  Future<void> _initHardwareForRole(EndpointRole role) async {
    if (!isPhysicalChannelSupported) return;
    final needsCamera = role == EndpointRole.receiver;
    await _ensureChannelInitialized(
      CommChannelId.optical,
      setupOpticalCamera: needsCamera,
    );
    await _ensureChannelInitialized(CommChannelId.acoustic);
    if (isVibrationSupported) {
      await _ensureChannelInitialized(CommChannelId.vibration);
    }
  }

  Future<void> initHardware() async {
    await _initHardwareForRole(_role);
  }

  Future<void> startHardwareChannels({EndpointRole? forRole}) async {
    if (!isPhysicalChannelSupported) {
      _statusMessage = 'Physical channels require a phone or Chrome browser';
      notifyListeners();
      return;
    }
    final role = forRole ?? _role;
    final selected = _selectedPhysicalChannel;
    await _initHardwareForRole(role);

    // Only run the channel the user picked — avoids mic/camera fighting each other.
    Future<void> startOne(CommChannelId id, {required bool rx}) async {
      switch (id) {
        case CommChannelId.optical:
          await _opticalChannel?.start(enableReceiver: rx);
        case CommChannelId.acoustic:
          await _acousticChannel?.start(enableReceiver: rx);
        case CommChannelId.vibration:
          if (isVibrationSupported) {
            await _vibrationChannel?.start(enableReceiver: rx);
          }
      }
    }

    if (selected != null) {
      // Stop other phys so they don't steal mic/camera/accel.
      for (final id in CommChannelId.values) {
        if (id == selected) continue;
        switch (id) {
          case CommChannelId.optical:
            await _opticalChannel?.stop();
          case CommChannelId.acoustic:
            await _acousticChannel?.stop();
          case CommChannelId.vibration:
            await _vibrationChannel?.stop();
        }
      }
      await startOne(selected, rx: role == EndpointRole.receiver);
    } else {
      await startOne(
        CommChannelId.optical,
        rx: role == EndpointRole.receiver,
      );
      await startOne(CommChannelId.acoustic, rx: role == EndpointRole.receiver);
      if (isVibrationSupported) {
        await startOne(
          CommChannelId.vibration,
          rx: role == EndpointRole.receiver,
        );
      }
    }

    _hardwareChannelsActive = true;
    logger.info(
      'Hardware channels started (${role.name}'
      '${selected != null ? ', ${channelIdToName(selected)}' : ''})',
    );
    _statusMessage = role == EndpointRole.receiver
        ? (selected != null
            ? 'Listening on ${channelIdToName(selected)}'
            : 'Hardware channels active — listening')
        : (selected != null
            ? 'Ready to send via ${channelIdToName(selected)}'
            : 'Hardware channels active — TX ready');
    if (role == EndpointRole.receiver) {
      _startHardwareReceiverListener();
    } else {
      _stopHardwareReceiverListener();
    }
    notifyListeners();
  }

  Future<void> stopHardwareChannels() async {
    _stopHardwareReceiverListener();
    await _opticalChannel?.stop();
    await _acousticChannel?.stop();
    await _vibrationChannel?.stop();
    _hardwareChannelsActive = false;
    logger.info('Hardware channels stopped');
    _statusMessage = 'Hardware channels stopped';
    notifyListeners();
  }

  Future<void> restartHardwareChannels() async {
    await stopHardwareChannels();
    await startHardwareChannels();
  }

  Future<void> runSimulation({Uint8List? data}) async {
    if (_running) return;
    final scenario = sim.getScenario(_scenarioId);
    if (scenario == null) return;

    _running = true;
    _lastSimResult = null;
    _liveLogs.clear();
    _senderSnapshot = null;
    _receiverSnapshot = null;
    _statusMessage = 'Running simulation: ${scenario.name}';
    notifyListeners();

    final payload = data ?? generateTestData(scenario.dataSize);
    final pair = scenario.createPair();
    final unsubA = pair.endpointA.logger.onLog(_addLog);
    final unsubB = pair.endpointB.logger.onLog(_addLog);

    final orchestrator = SimulationOrchestrator(pair);
    orchestrator.onUpdate = (s, r) {
      _senderSnapshot = s;
      _receiverSnapshot = r;
      notifyListeners();
    };

    try {
      _lastSimResult = await orchestrator.runTransfer(payload);
      _senderSnapshot = _lastSimResult!.senderSnapshot;
      _receiverSnapshot = _lastSimResult!.receiverSnapshot;
      _lastReceivedData = _lastSimResult!.dataMatch ? payload : null;
      _statusMessage = _lastSimResult!.success
          ? 'Simulation succeeded (${_lastSimResult!.durationMs}ms)'
          : 'Simulation failed';
    } finally {
      unsubA();
      unsubB();
      _running = false;
      notifyListeners();
    }
  }

  Future<void> runHardwareTransfer(
    Uint8List data, {
    CommChannelId? forcedChannel,
  }) async {
    if (_running) return;
    if (!isPhysicalChannelSupported) {
      _statusMessage = 'Hardware transfer requires a phone or Chrome browser';
      notifyListeners();
      return;
    }

    final channel = forcedChannel ?? _selectedPhysicalChannel;
    _running = true;
    _lastTransferSucceeded = false;
    _cancelRequested = false;
    _statusMessage = 'Starting hardware transfer...';
    _liveLogs.clear();
    notifyListeners();

    await startHardwareChannels(forRole: _role);
    final unsub = logger.onLog(_addLog);
    TransferManager? tm;
    try {
      final cm = await createChannelManagerForMode(
        OperationMode.hardware,
        logger,
        optical: _opticalChannel,
        acoustic: _acousticChannel,
        vibration: _vibrationChannel,
        hardwareRole: _role,
      );
      tm = TransferManager(
        role: _role,
        logger: logger,
        channelManager: cm,
        config: TransferManagerConfig(
          mode: OperationMode.hardware,
          transferMode: channel == CommChannelId.vibration
              ? TransferMode.unicast
              : _transferMode,
          peerDiscoveryTimeoutMs: 20000,
          peerInactivityTimeoutMs: 45000,
          enableAdaptiveSwitching: false,
          forcedChannel: channel,
          isCancelled: () => _cancelRequested,
        ),
      );
      tm.onSnapshot = (s) {
        if (_role == EndpointRole.sender) {
          _senderSnapshot = s;
        } else {
          _receiverSnapshot = s;
        }
        notifyListeners();
      };

      _lastReceivedData = await tm.runTransfer(data);
      _lastTransferSucceeded = tm.stateMachine.state == TransferState.completed;
      if (_lastReceivedData != null && _role == EndpointRole.receiver) {
        _addIncomingChat(_lastReceivedData!);
      }
      if (_lastTransferSucceeded) {
        if (_role == EndpointRole.sender) {
          _statusMessage = _transferMode == TransferMode.broadcast
              ? 'Broadcast sent (${data.length} bytes) — all listeners should receive'
              : 'Message delivered (${data.length} bytes)';
        } else if (_lastReceivedData != null) {
          _statusMessage =
              'Received ${_lastReceivedData!.length} bytes: ${String.fromCharCodes(_lastReceivedData!)}';
        }
      } else if (_role == EndpointRole.sender) {
        _statusMessage = _transferMode == TransferMode.broadcast
            ? 'Broadcast failed — ensure receivers are in Receive + Live mode'
            : 'No device found — set other device to Receive, tap Start, then retry';
      } else {
        _statusMessage =
            'Receiver waiting — align devices and ensure sender is transmitting';
      }
    } catch (e) {
      logger.error('Hardware transfer failed: $e');
      _statusMessage = 'Transfer failed — tap Start, then retry';
    } finally {
      unsub();
      await tm?.shutdown();
      _running = false;
      if (_cancelRequested) {
        opticalTransmitterState.setTransmitting(false);
        vibrationTransmitterState.setTransmitting(false);
        _statusMessage = 'Transfer cancelled';
      }
      await _restoreHardwareAfterTransfer();
      notifyListeners();
    }
  }

  Future<void> sendHardwareHello() async {
    await sendHardwareMessage('HELLO');
  }

  Future<void> sendHardwareMessage(String text) async {
    await sendChatText(text);
  }

  Future<void> _ensureChannelReady(
    CommChannelId channelId, {
    bool? enableReceiver,
  }) async {
    if (!isPhysicalChannelSupported) {
      throw StateError('Physical channels require a phone or Chrome browser');
    }
    final rx = enableReceiver ?? (_role == EndpointRole.receiver);
    await _ensureChannelInitialized(
      channelId,
      setupOpticalCamera: channelId == CommChannelId.optical && rx,
    );
    switch (channelId) {
      case CommChannelId.optical:
        if (!(_opticalChannel?.isAvailable() ?? false)) {
          await _opticalChannel?.start(
            enableReceiver: enableReceiver ?? (_role == EndpointRole.receiver),
          );
          _hardwareChannelsActive = true;
        }
      case CommChannelId.acoustic:
        if (!(_acousticChannel?.isAvailable() ?? false)) {
          await _acousticChannel?.start(enableReceiver: true);
          _hardwareChannelsActive = true;
        }
      case CommChannelId.vibration:
        if (!(_vibrationChannel?.isAvailable() ?? false)) {
          await _vibrationChannel?.start(
            enableReceiver: enableReceiver ?? (_role == EndpointRole.receiver),
          );
          _hardwareChannelsActive = true;
        }
    }
  }

  Future<void> _transmitOnChannel(
    CommChannelId channelId,
    Uint8List payload, {
    bool? enableReceiver,
  }) async {
    await _ensureChannelReady(channelId, enableReceiver: enableReceiver);
    final channel = switch (channelId) {
      CommChannelId.optical => _opticalChannel,
      CommChannelId.acoustic => _acousticChannel,
      CommChannelId.vibration => _vibrationChannel,
    };
    if (channel == null || !channel.isAvailable()) {
      throw StateError('${channelIdToName(channelId)} channel not available');
    }
    logger.info('Direct TX on ${channelIdToName(channelId)} (${payload.length} bytes)');
    await channel.transmit(payload);
  }

  /// Flash the screen with an optical test pattern (sender phone).
  Future<void> testOpticalFlash() async {
    if (_running || !isPhysicalChannelSupported) return;
    _running = true;
    final unsub = logger.onLog(_addLog);
    notifyListeners();
    try {
      await _transmitOnChannel(
        CommChannelId.optical,
        Uint8List.fromList('FLASH'.codeUnits),
        enableReceiver: false,
      );
      _statusMessage = 'Optical QR test complete';
    } catch (e) {
      logger.error('Optical test failed: $e');
      _statusMessage = 'Optical test failed — tap Start Channels';
    } finally {
      unsub();
      _running = false;
      notifyListeners();
    }
  }

  /// Pulse the vibration motor with a test pattern (sender phone).
  Future<void> testVibration() async {
    if (_running || !isVibrationSupported) return;
    _running = true;
    final unsub = logger.onLog(_addLog);
    notifyListeners();
    try {
      await _transmitOnChannel(
        CommChannelId.vibration,
        Uint8List.fromList('VIB'.codeUnits),
        enableReceiver: false,
      );
      _statusMessage = 'Vibration test complete';
    } catch (e) {
      logger.error('Vibration test failed: $e');
      _statusMessage = 'Vibration test failed — tap Start Channels';
    } finally {
      unsub();
      _running = false;
      notifyListeners();
    }
  }

  Future<void> runPerformanceComparison() async {
    if (_running) return;
    _running = true;
    _statusMessage = 'Running performance comparison...';
    _comparisonResults = [];
    notifyListeners();

    try {
      _comparisonResults = await PerformanceComparator().runComparison();
      _statusMessage = 'Comparison complete';
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> runAllScenarios() async {
    if (_running) return;
    _running = true;
    var passed = 0;
    _statusMessage = 'Running all scenarios...';
    notifyListeners();

    try {
      for (final scenario in sim.scenarios) {
        final pair = scenario.createPair();
        final result = await SimulationOrchestrator(pair).runTransfer(
          generateTestData(scenario.dataSize),
        );
        if (result.success) passed++;
      }
      _statusMessage = '$passed/${sim.scenarios.length} scenarios passed';
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  void _addLog(LogEntry entry) {
    _liveLogs.add(entry);
    notifyListeners();
  }

  void _startHardwareReceiverListener() {
    _hardwareListenTimer?.cancel();
    if (_role != EndpointRole.receiver || !_hardwareChannelsActive) return;
    _hardwareListenTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => unawaited(_pollHardwareReceiver()),
    );
  }

  void _stopHardwareReceiverListener() {
    _hardwareListenTimer?.cancel();
    _hardwareListenTimer = null;
    _incomingIdleTimer?.cancel();
    _incomingIdleTimer = null;
    _incomingPacketBuffer.clear();
    _incomingExpectedPackets = null;
    _incomingTransferId = null;
    _incomingBufferedCount = 0;
    _deliveredTransferIds.clear();
  }

  Future<void> _pollHardwareReceiver() async {
    if (!_hardwareChannelsActive || _role != EndpointRole.receiver || _running) {
      return;
    }

    final packets = <DecodedPacket>[];
    final selected = _selectedPhysicalChannel;
    if (selected == null || selected == CommChannelId.optical) {
      packets.addAll(await _opticalChannel?.receive() ?? const []);
    }
    if (selected == null || selected == CommChannelId.acoustic) {
      packets.addAll(await _acousticChannel?.receive() ?? const []);
    }
    if (isVibrationSupported &&
        (selected == null || selected == CommChannelId.vibration)) {
      packets.addAll(await _vibrationChannel?.receive() ?? const []);
    }

    // When a channel is selected, only keep packets from that channel.
    final filtered = selected == null
        ? packets
        : packets.where((p) => p.channelId == selected).toList();

    for (final packet in filtered) {
      switch (packet.packetType) {
        case PacketType.discovery:
          if (_transferMode == TransferMode.unicast) {
            await _replyDiscovery(packet);
          }
        case PacketType.data:
          await _handleIncomingData(packet);
        case PacketType.transferComplete:
          if (packet.totalPackets > 0) {
            _incomingExpectedPackets = packet.totalPackets;
          }
          _tryDeliverIncomingMessage(forceIncompleteCheck: true);
        default:
          break;
      }
    }

    await _pollDirectEnvelopes();
  }

  Future<void> _pollDirectEnvelopes() async {
    final envelopes = <Uint8List>[
      ...await _opticalChannel?.receiveEnvelopes() ?? const [],
      ...await _acousticChannel?.receiveEnvelopes() ?? const [],
    ];
    for (final env in envelopes) {
      _addIncomingChat(env);
      // Do not wipe reassembler/dedup here — only clear drained envelope buffer.
      _opticalChannel?.clearReceiveCaches(resetDedup: false);
      unawaited(_opticalChannel?.ensureReceiverStreaming());
    }
  }

  CommChannelId _replyChannelFor(DecodedPacket packet) {
    if (packet.channelId == CommChannelId.optical &&
        (_acousticChannel?.isAvailable() ?? false)) {
      return CommChannelId.acoustic;
    }
    return packet.channelId;
  }

  Future<void> _replyDiscovery(DecodedPacket packet) async {
    final replyChannel = _replyChannelFor(packet);
    final response = packetCodec.encode(
      PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: packet.sessionId,
        transferId: packet.transferId,
        packetType: PacketType.discoveryResponse,
        channelId: replyChannel,
        sequenceNumber: 0,
        payloadLength: hardwareDiscoveryPayload.length,
      ),
      hardwareDiscoveryPayload,
    );
    await _transmitOnChannel(
      replyChannel,
      response,
      enableReceiver: true,
    );
    logger.discovery(
      'Responded to discovery on ${channelIdToName(packet.channelId)}',
    );
  }

  Future<void> _handleIncomingData(DecodedPacket packet) async {
    // Broadcast receivers must stay quiet — ACKs (especially acoustic) drown out RX.
    if (_transferMode == TransferMode.unicast) {
      await _sendAck(packet);
    }

    if (_deliveredTransferIds.contains(packet.transferId)) {
      return;
    }

    if (_incomingTransferId != packet.transferId) {
      _incomingTransferId = packet.transferId;
      _incomingPacketBuffer.clear();
      _incomingExpectedPackets = null;
      _incomingBufferedCount = 0;
    }

    if (packet.totalPackets > 0) {
      _incomingExpectedPackets = packet.totalPackets;
    }

    _incomingPacketBuffer[packet.sequenceNumber] = packet.payload;
    _incomingBufferedCount = _incomingPacketBuffer.length;
    _statusMessage = _incomingExpectedPackets != null
        ? 'Receiving… $_incomingBufferedCount/$_incomingExpectedPackets packets'
        : 'Receiving… $_incomingBufferedCount packet(s)';
    notifyListeners();

    _armIncomingIdleTimer();
    _tryDeliverIncomingMessage();
  }

  Future<void> _sendAck(DecodedPacket packet) async {
    final replyChannel = _replyChannelFor(packet);
    final ack = packetCodec.encode(
      PacketHeader(
        protocolVersion: protocolVersion,
        sessionId: packet.sessionId,
        transferId: packet.transferId,
        packetType: PacketType.ack,
        channelId: replyChannel,
        sequenceNumber: packet.sequenceNumber,
        payloadLength: 0,
      ),
      Uint8List(0),
    );
    await _transmitOnChannel(replyChannel, ack, enableReceiver: true);
  }

  void _armIncomingIdleTimer() {
    _incomingIdleTimer?.cancel();
    _incomingIdleTimer = Timer(const Duration(milliseconds: 1800), () {
      _tryDeliverIncomingMessage(forceIncompleteCheck: true);
    });
  }

  void _tryDeliverIncomingMessage({bool forceIncompleteCheck = false}) {
    if (_incomingPacketBuffer.isEmpty) return;

    final transferId = _incomingTransferId;
    if (transferId != null && _deliveredTransferIds.contains(transferId)) {
      _incomingPacketBuffer.clear();
      _incomingExpectedPackets = null;
      _incomingTransferId = null;
      _incomingBufferedCount = 0;
      return;
    }

    final maxSeq = _incomingPacketBuffer.keys.reduce((a, b) => a > b ? a : b);
    final expected = _incomingExpectedPackets;

    // Wait until we know the total and have every packet — never deliver early.
    if (expected != null) {
      if (_incomingPacketBuffer.length < expected) return;
      for (var i = 1; i <= expected; i++) {
        if (!_incomingPacketBuffer.containsKey(i)) return;
      }
    } else {
      // Legacy / unknown total: require contiguous 1..maxSeq, and either a
      // single packet that fully decodes, or idle timeout after multi-packet.
      for (var i = 1; i <= maxSeq; i++) {
        if (!_incomingPacketBuffer.containsKey(i)) return;
      }
      if (maxSeq > 1 && !forceIncompleteCheck) return;
    }

    final endSeq = expected ?? maxSeq;
    final parts = <Uint8List>[];
    for (var i = 1; i <= endSeq; i++) {
      final part = _incomingPacketBuffer[i];
      if (part == null) return;
      parts.add(part);
    }

    final totalLength = parts.fold<int>(0, (sum, p) => sum + p.length);
    final assembled = Uint8List(totalLength);
    var offset = 0;
    for (final part in parts) {
      assembled.setRange(offset, offset + part.length, part);
      offset += part.length;
    }

    // Reject truncated chat envelopes (e.g. first chunk of an image).
    if (!ChatPayloadCodec.looksComplete(assembled)) {
      if (!forceIncompleteCheck) return;
      logger.warning(
        'Incomplete payload (${assembled.length} B) — still waiting for packets',
      );
      _statusMessage =
          'Incomplete data (${assembled.length} B) — keep devices aligned';
      notifyListeners();
      return;
    }

    _incomingIdleTimer?.cancel();
    _incomingIdleTimer = null;
    _incomingPacketBuffer.clear();
    _incomingExpectedPackets = null;
    _incomingBufferedCount = 0;
    if (transferId != null) _deliveredTransferIds.add(transferId);
    _incomingTransferId = null;
    _addIncomingChat(assembled);
    _resetPhysicalReceiveCaches();
    unawaited(_opticalChannel?.ensureReceiverStreaming());
    _statusMessage = 'Message received — still listening for more';
    notifyListeners();
  }

  @override
  void dispose() {
    _stopHardwareReceiverListener();
    _incomingIdleTimer?.cancel();
    _opticalChannel?.dispose();
    _acousticChannel?.dispose();
    _vibrationChannel?.dispose();
    super.dispose();
  }
}

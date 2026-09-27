import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/transport/reliable_transport.dart';
import 'package:adaptive_physical_communication/core/types/types.dart';

/// Physical-layer bit/symbol timing tuned for real phone hardware.
const int hardwareOpticalBitMs = 35;

/// Fast FSK symbols — short text should finish in a few seconds.
const int hardwareAcousticSymbolMs = 18;

/// How many times to replay acoustic TX so nearby receivers catch it.
const int hardwareAcousticTxRepeatCount = 3;

/// Gap between acoustic TX replays (ms).
const int hardwareAcousticTxRepeatGapMs = 350;

/// Leading silence before acoustic TX so the mic AGC settles.
const int hardwareAcousticLeadSilenceMs = 180;

/// Protocol timeouts aligned with real PHY speed.
const hardwareTransportConfig = TransportConfig(
  ackTimeoutMs: 20000,
  maxRetries: 8,
  windowSize: 4,
);

/// Legacy protocol path packet sizes (direct envelope mode preferred on hardware).
const int hardwareOpticalPacketSize = 1400;
const int hardwareAcousticPacketSize = 512;
const int hardwareVibrationPacketSize = 48;

/// Max envelope size for one-shot acoustic direct broadcast.
const int hardwareAcousticDirectMaxBytes = 900;

/// Max envelope size over the fountain sound modem.
///
/// Not a protocol limit — at roughly 25 B/s in a normal room this is already
/// about six minutes of playback, and beyond that the light channel is the
/// right tool.
const int acousticFountainMaxBytes = 8192;

TransmissionConfig hardwareTransmissionConfigFor(CommChannelId channel) {
  return TransmissionConfig(
    packetSize: switch (channel) {
      CommChannelId.optical => hardwareOpticalPacketSize,
      CommChannelId.acoustic => hardwareAcousticPacketSize,
      CommChannelId.vibration => hardwareVibrationPacketSize,
    },
  );
}

/// Compact discovery frame — fits in one fast beacon.
Uint8List get hardwareDiscoveryPayload => Uint8List.fromList([0xDC, 0x01]);

int estimateHardwareTxMs(int byteCount) {
  const bitsPerByte = 8;
  const preambleBits = 8;
  final totalBits = preambleBits + byteCount * bitsPerByte;
  return totalBits * hardwareAcousticSymbolMs;
}

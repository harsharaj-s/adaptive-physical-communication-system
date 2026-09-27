import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_csk_overlay.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_fountain_qr_overlay.dart';

/// Shows the active optical TX overlay (fountain QR or CSK).
class OpticalActiveOverlay extends StatelessWidget {
  const OpticalActiveOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: opticalTransmitterState,
      builder: (context, _) {
        if (!opticalTransmitterState.transmitting) {
          return const SizedBox.shrink();
        }
        if (opticalTransmitterState.isFountainQr) {
          return const OpticalFountainQrOverlay();
        }
        return const OpticalCskOverlay();
      },
    );
  }
}

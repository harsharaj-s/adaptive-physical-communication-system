import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/ui/widgets/qr_bitmap_view.dart';

/// Full-bleed fountain QR transmitter overlay (white field + black modules).
///
/// The stream never ends on its own (bar a long safety cap): the sender has
/// no way to learn that the receiver finished, so the user stops it.
class OpticalFountainQrOverlay extends StatelessWidget {
  const OpticalFountainQrOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: opticalTransmitterState,
      builder: (context, _) {
        final tx = opticalTransmitterState;
        if (!tx.transmitting || !tx.isFountainQr) {
          return const SizedBox.shrink();
        }
        final bitmap = tx.qrBitmap;
        if (bitmap == null) {
          return const ColoredBox(color: Colors.white);
        }

        final kb = tx.fountainFileLen / 1000;
        return Material(
          color: Colors.white,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      const Text(
                        'Streaming… tap Stop when the receiver shows DONE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${tx.profileLabel} · ${tx.fountainBlockLen} B/frame'
                        '${tx.fountainFileLen > 0 ? ' · ${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB' : ''}'
                        ' · K=${tx.fountainK} · frame ${tx.chunkIndex}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: QrBitmapView(bitmap: bitmap),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => onOpticalTransmitCancel?.call(),
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

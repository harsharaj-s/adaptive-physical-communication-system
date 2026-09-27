import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';

/// Full-screen 2×2 Color Shift Keying mosaic for optical TX.
class OpticalCskOverlay extends StatelessWidget {
  const OpticalCskOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: opticalTransmitterState,
      builder: (context, _) {
        if (!opticalTransmitterState.transmitting) {
          return const SizedBox.shrink();
        }

        final cells = opticalTransmitterState.cskCells;
        final guard = opticalTransmitterState.showingGuard;
        final index = opticalTransmitterState.chunkIndex;
        final total = opticalTransmitterState.chunkTotal;

        return Material(
          color: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 52),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        total > 0
                            ? 'CSK light TX — byte $index / $total'
                            : 'CSK light TX',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: guard || cells == null || cells.length != 4
                              ? const ColoredBox(color: Colors.black)
                              : Column(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(child: ColoredBox(color: cells[0])),
                                          Expanded(child: ColoredBox(color: cells[1])),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(child: ColoredBox(color: cells[2])),
                                          Expanded(child: ColoredBox(color: cells[3])),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Receiver camera reads red / green / blue / white cells',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: FilledButton.tonalIcon(
                    onPressed: onOpticalTransmitCancel,
                    icon: const Icon(Icons.close, size: 20),
                    label: const Text('Cancel'),
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

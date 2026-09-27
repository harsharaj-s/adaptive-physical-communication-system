import 'package:flutter/material.dart';



import 'package:adaptive_physical_communication/core/types/types.dart';

import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';



class EndpointPanel extends StatelessWidget {

  const EndpointPanel({

    super.key,

    required this.title,

    required this.snapshot,

    this.emptyMessage,

  });



  final String title;

  final DashboardSnapshot? snapshot;

  final String? emptyMessage;



  StatusTone _stateTone(TransferState state) {
    return switch (state) {
      TransferState.completed => StatusTone.success,
      TransferState.failed => StatusTone.error,
      TransferState.degraded ||
      TransferState.switchingChannel ||
      TransferState.recovering =>
        StatusTone.warning,
      _ => StatusTone.info,
    };
  }



  @override

  Widget build(BuildContext context) {

    final snap = snapshot;



    return Card(

      clipBehavior: Clip.antiAlias,

      child: Padding(

        padding: const EdgeInsets.all(16),

        child: snap == null
            ? EmptyState(
                icon: Icons.monitor_heart_outlined,
                message: emptyMessage ?? 'Waiting for transfer',
                subtitle: 'Metrics update during active transfer',
              )

            : SingleChildScrollView(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [

                    Text(

                      title,

                      style: Theme.of(context).textTheme.titleMedium?.copyWith(

                            fontWeight: FontWeight.bold,

                          ),

                    ),

                    const SizedBox(height: 8),

                    StatusChip(

                      label: transferStateLabel(snap.state),

                      tone: _stateTone(snap.state),

                    ),

                    const Divider(height: 20),

                    _MetricRow(

                      label: 'Channel',

                      value: snap.currentChannel != null

                          ? channelIdToName(snap.currentChannel!)

                          : 'N/A',

                    ),

                    _MetricRow(

                      label: 'Score',

                      value: snap.channelScore.toStringAsFixed(2),

                    ),

                    _MetricRow(

                      label: 'Confidence',

                      value: snap.channelConfidence.toStringAsFixed(2),

                    ),

                    if (snap.metrics != null) ...[

                      _MetricRow(

                        label: 'Throughput',

                        value:

                            '${(snap.metrics!.throughput / 1000).toStringAsFixed(1)} kbps',

                      ),

                      _MetricRow(

                        label: 'Packet Loss',

                        value: '${(snap.metrics!.packetLoss * 100).toStringAsFixed(1)}%',

                        valueColor: snap.metrics!.packetLoss > 0.1

                            ? Colors.redAccent

                            : Colors.greenAccent,

                      ),

                      _MetricRow(

                        label: 'Latency',

                        value: '${snap.metrics!.latency.toStringAsFixed(0)} ms',

                      ),

                    ],

                    if (snap.progress != null) ...[

                      const SizedBox(height: 8),

                      LinearProgressIndicator(

                        value: snap.progress!.progressPercent / 100,

                        minHeight: 8,

                        borderRadius: BorderRadius.circular(4),

                      ),

                      const SizedBox(height: 8),

                      _MetricRow(

                        label: 'Progress',

                        value: '${snap.progress!.progressPercent.toStringAsFixed(0)}%',

                      ),

                      _MetricRow(

                        label: 'Packets',

                        value:

                            '${snap.progress!.acknowledgedPackets} / ${snap.progress!.totalPackets}',

                      ),

                      _MetricRow(

                        label: 'Retries',

                        value: '${snap.progress!.retryCount}',

                      ),

                    ],

                    if (snap.channelScores.isNotEmpty) ...[

                      const SizedBox(height: 12),

                      Text(

                        'CHANNELS',

                        style: Theme.of(context).textTheme.labelSmall?.copyWith(

                              letterSpacing: 1.2,

                              color: Colors.white54,

                            ),

                      ),

                      const SizedBox(height: 8),

                      ...snap.channelScores.entries.map(

                        (e) => _ChannelScoreBar(name: e.key, score: e.value),

                      ),

                    ],

                    if (snap.switchEvents.isNotEmpty) ...[

                      const SizedBox(height: 12),

                      Text(

                        'SWITCH EVENTS',

                        style: Theme.of(context).textTheme.labelSmall?.copyWith(

                              letterSpacing: 1.2,

                              color: Colors.white54,

                            ),

                      ),

                      ...snap.switchEvents.map(

                        (e) => Padding(

                          padding: const EdgeInsets.only(top: 4),

                          child: Text(

                            '${channelIdToName(e.fromChannel)} → ${channelIdToName(e.toChannel)} @ pkt ${e.lastConfirmedPacket}',

                            style: const TextStyle(

                              fontSize: 12,

                              color: Colors.purpleAccent,

                            ),

                          ),

                        ),

                      ),

                    ],

                  ],

                ),

              ),

      ),

    );

  }

}



class _MetricRow extends StatelessWidget {

  const _MetricRow({

    required this.label,

    required this.value,

    this.valueColor,

  });



  final String label;

  final String value;

  final Color? valueColor;



  @override

  Widget build(BuildContext context) {

    return Padding(

      padding: const EdgeInsets.symmetric(vertical: 3),

      child: Row(

        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [

          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),

          Text(

            value,

            style: TextStyle(

              fontWeight: FontWeight.w600,

              color: valueColor,

              fontFeatures: const [FontFeature.tabularFigures()],

            ),

          ),

        ],

      ),

    );

  }

}



class _ChannelScoreBar extends StatelessWidget {

  const _ChannelScoreBar({required this.name, required this.score});



  final String name;

  final double score;



  @override

  Widget build(BuildContext context) {

    return Padding(

      padding: const EdgeInsets.symmetric(vertical: 4),

      child: Row(

        children: [

          SizedBox(

            width: 72,

            child: Text(name, style: const TextStyle(fontSize: 12)),

          ),

          Expanded(

            child: ClipRRect(

              borderRadius: BorderRadius.circular(4),

              child: LinearProgressIndicator(

                value: score.clamp(0, 1),

                minHeight: 8,

                backgroundColor: Colors.white12,

              ),

            ),

          ),

          const SizedBox(width: 8),

          SizedBox(

            width: 36,

            child: Text(

              score.toStringAsFixed(2),

              style: const TextStyle(fontSize: 12),

              textAlign: TextAlign.right,

            ),

          ),

        ],

      ),

    );

  }

}


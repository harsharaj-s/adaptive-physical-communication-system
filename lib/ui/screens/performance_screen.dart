import 'package:flutter/material.dart';



import 'package:adaptive_physical_communication/core/performance/performance_comparator.dart';

import 'package:adaptive_physical_communication/main.dart';

import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';



class PerformanceScreen extends StatelessWidget {

  const PerformanceScreen({super.key});



  @override

  Widget build(BuildContext context) {

    final app = AppProvider.of(context);

    final wide = isWideLayout(context);



    return Scaffold(

      appBar: AppBar(title: const BrandedTitle('Performance Comparison')),

      body: PageContainer(

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            SectionCard(

              title: 'Baseline Comparison',

              subtitle: 'Fixed-channel vs adaptive strategy (simulation)',

              icon: Icons.analytics,

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(

                    'Compares fixed optical, fixed acoustic, and adaptive strategies using the simulation engine.',

                    style: Theme.of(context).textTheme.bodySmall?.copyWith(

                          color: Colors.white70,

                        ),

                  ),

                  const SizedBox(height: 12),

                  FilledButton.icon(

                    onPressed: app.running ? null : app.runPerformanceComparison,

                    icon: app.running

                        ? const SizedBox(

                            width: 16,

                            height: 16,

                            child: CircularProgressIndicator(strokeWidth: 2),

                          )

                        : const Icon(Icons.science),

                    label: Text(app.running ? 'Running…' : 'Run Comparison'),

                  ),

                ],

              ),

            ),

            const SizedBox(height: 16),

            Expanded(

              child: app.comparisonResults.isEmpty

                  ? const EmptyState(

                      icon: Icons.bar_chart,

                      message: 'Run comparison to see results',

                      subtitle: 'Results appear here with throughput, loss, and switch counts',

                    )

                  : wide

                      ? GridView.builder(

                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(

                            crossAxisCount: screenSizeOf(context) == ScreenSize.desktop ? 3 : 2,

                            mainAxisSpacing: 12,

                            crossAxisSpacing: 12,

                            childAspectRatio: 1.3,

                          ),

                          itemCount: app.comparisonResults.length,

                          itemBuilder: (context, i) =>

                              _ResultCard(result: app.comparisonResults[i]),

                        )

                      : ListView.separated(

                          itemCount: app.comparisonResults.length,

                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),

                          itemBuilder: (context, i) =>

                              _ResultCard(result: app.comparisonResults[i]),

                        ),

            ),

          ],

        ),

      ),

    );

  }

}



class _ResultCard extends StatelessWidget {

  const _ResultCard({required this.result});



  final StrategyResult result;



  @override

  Widget build(BuildContext context) {

    return Card(

      child: Padding(

        padding: const EdgeInsets.all(16),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(

              children: [

                Icon(

                  result.success ? Icons.check_circle : Icons.error,

                  color: result.success ? Colors.greenAccent : Colors.redAccent,

                ),

                const SizedBox(width: 8),

                Expanded(

                  child: Text(

                    strategyLabel(result.strategy),

                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),

                  ),

                ),

              ],

            ),

            const SizedBox(height: 8),

            _row('Duration', '${result.durationMs} ms'),

            _row('Throughput', '${(result.throughput / 1000).toStringAsFixed(1)} kbps'),

            _row('Goodput', '${(result.goodput / 1024).toStringAsFixed(1)} KB/s'),

            _row('Packet Loss', '${(result.packetLoss * 100).toStringAsFixed(1)}%'),

            _row('Retransmissions', '${result.retransmissions}'),

            _row('Channel Switches', '${result.switchCount}'),

          ],

        ),

      ),

    );

  }



  Widget _row(String label, String value) {

    return Padding(

      padding: const EdgeInsets.symmetric(vertical: 2),

      child: Row(

        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [

          Text(label, style: const TextStyle(color: Colors.white70)),

          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),

        ],

      ),

    );

  }

}


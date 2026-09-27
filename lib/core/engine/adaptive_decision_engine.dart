import 'package:adaptive_physical_communication/core/types/types.dart';

class NormalizedMetrics {
  const NormalizedMetrics({
    required this.throughput,
    required this.reliability,
    required this.latency,
    required this.confidence,
    required this.stability,
  });

  final double throughput;
  final double reliability;
  final double latency;
  final double confidence;
  final double stability;
}

class MetricNormalizer {
  final double maxThroughput = 25000;
  final double maxLatency = 500;

  NormalizedMetrics normalize(ChannelMetrics metrics) => NormalizedMetrics(
        throughput: (metrics.throughput / maxThroughput).clamp(0.0, 1.0),
        reliability: metrics.reliability.clamp(0.0, 1.0),
        latency: (1 - metrics.latency / maxLatency).clamp(0.0, 1.0),
        confidence: metrics.confidence.clamp(0.0, 1.0),
        stability: metrics.stability.clamp(0.0, 1.0),
      );

  NormalizedMetrics normalizeFromTestResult(ChannelTestResult result) {
    final reliability =
        result.packetsSent > 0 ? result.packetsReceived / result.packetsSent : 0.0;
    return normalize(ChannelMetrics(
      throughput: result.throughput,
      packetLoss: result.packetLossRate,
      latency: result.latency,
      reliability: reliability,
      errorRate: result.packetLossRate,
      confidence: result.confidence,
      stability: result.stability,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}

class ChannelScorer {
  ChannelScorer({ScoringWeights weights = defaultScoringWeights})
      : _weights = weights;

  ScoringWeights _weights;
  final MetricNormalizer _normalizer = MetricNormalizer();

  void setWeights(ScoringWeights weights) => _weights = weights;

  double scoreMetrics(ChannelMetrics metrics) =>
      _calculateScore(_normalizer.normalize(metrics));

  double scoreTestResult(ChannelTestResult result) =>
      _calculateScore(_normalizer.normalizeFromTestResult(result));

  double _calculateScore(NormalizedMetrics n) =>
      _weights.throughput * n.throughput +
      _weights.reliability * n.reliability +
      _weights.latency * n.latency +
      _weights.confidence * n.confidence +
      _weights.stability * n.stability;

  List<({CommChannelId channel, double score, double confidence})> rankChannels(
    List<ChannelTestResult> results,
  ) {
    final ranked = results
        .map((r) => (
              channel: r.channel,
              score: scoreTestResult(r),
              confidence: r.confidence,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }
}

class AdaptiveDecisionEngine {
  AdaptiveDecisionEngine({
    ChannelScorer? scorer,
    this.hysteresisThreshold = switchHysteresisThreshold,
    this.degradationThresholdValue = degradationThreshold,
  }) : scorer = scorer ?? ChannelScorer();

  final ChannelScorer scorer;
  final double hysteresisThreshold;
  final double degradationThresholdValue;

  ChannelDecision selectBestChannel(List<ChannelTestResult> testResults) {
    if (testResults.isEmpty) {
      throw StateError('No channel test results available');
    }

    final ranked = scorer.rankChannels(testResults);
    final best = ranked.first;
    var reason = 'Highest composite channel score';

    if (ranked.length > 1) {
      final bestResult =
          testResults.firstWhere((r) => r.channel == best.channel);
      final secondResult =
          testResults.firstWhere((r) => r.channel == ranked[1].channel);
      if (bestResult.throughput > secondResult.throughput) {
        reason = 'Higher throughput and reliability';
      } else if (bestResult.packetLossRate < secondResult.packetLossRate) {
        reason = 'Lower packet loss';
      } else if (bestResult.latency < secondResult.latency) {
        reason = 'Lower latency';
      }
    }

    return ChannelDecision(
      selectedChannel: best.channel,
      score: best.score,
      confidence: best.confidence,
      reason: reason,
    );
  }

  bool isDegraded(double currentScore) =>
      currentScore < degradationThresholdValue;

  bool shouldSwitch(double currentScore, double alternativeScore) {
    if (!isDegraded(currentScore)) return false;
    return alternativeScore - currentScore >= hysteresisThreshold;
  }

  ({bool shouldSwitch, String reason, double currentScore, double alternativeScore})
      evaluateSwitch(
    CommChannelId currentChannel,
    ChannelMetrics currentMetrics,
    ChannelTestResult alternativeResult,
  ) {
    final currentScore = scorer.scoreMetrics(currentMetrics);
    final alternativeScore = scorer.scoreTestResult(alternativeResult);
    final switchNeeded = shouldSwitch(currentScore, alternativeScore);

    var reason = 'No switch needed';
    if (switchNeeded) {
      reason =
          'Switching ${channelIdToName(currentChannel)} → ${channelIdToName(alternativeResult.channel)}: '
          '${alternativeScore.toStringAsFixed(2)} vs ${currentScore.toStringAsFixed(2)}';
    } else if (isDegraded(currentScore)) {
      reason =
          'Degraded but hysteresis not met (${(alternativeScore - currentScore).toStringAsFixed(2)} < $hysteresisThreshold)';
    }

    return (
      shouldSwitch: switchNeeded,
      reason: reason,
      currentScore: currentScore,
      alternativeScore: alternativeScore,
    );
  }
}

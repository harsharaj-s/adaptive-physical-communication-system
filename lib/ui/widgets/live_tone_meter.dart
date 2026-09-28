import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/tone_timeline.dart';
import 'package:adaptive_physical_communication/core/platform/acoustic_spectrum_state.dart';

/// Live frequency readout for the sound channel.
///
/// [LiveToneMeter.sending] shows the tones the speaker is playing right now,
/// read from the burst's tone schedule; [LiveToneMeter.hearing] shows the
/// strongest frequencies the microphone picks up. Side by side on two phones,
/// the numbers should match when the sound is getting through.
class LiveToneMeter extends StatefulWidget {
  const LiveToneMeter.sending({super.key}) : sending = true;
  const LiveToneMeter.hearing({super.key}) : sending = false;

  final bool sending;

  @override
  State<LiveToneMeter> createState() => _LiveToneMeterState();
}

class _LiveToneMeterState extends State<LiveToneMeter> {
  /// Repaints the sender readout; symbols are tens of milliseconds long.
  static const _txRefresh = Duration(milliseconds: 50);

  Timer? _txTimer;

  @override
  void initState() {
    super.initState();
    acousticSpectrumState.addListener(_onSpectrum);
    _syncTxTimer();
  }

  @override
  void dispose() {
    acousticSpectrumState.removeListener(_onSpectrum);
    _txTimer?.cancel();
    super.dispose();
  }

  void _onSpectrum() {
    _syncTxTimer();
    if (mounted) setState(() {});
  }

  void _syncTxTimer() {
    final wanted = widget.sending && acousticSpectrumState.txTones != null;
    if (wanted && _txTimer == null) {
      _txTimer = Timer.periodic(_txRefresh, (_) {
        if (mounted) setState(() {});
      });
    } else if (!wanted && _txTimer != null) {
      _txTimer!.cancel();
      _txTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = acousticSpectrumState;
    final accent =
        widget.sending ? Colors.amberAccent : Colors.lightBlueAccent;

    final String headline;
    final String detail;
    final List<double> tones;
    Float32List? bands;

    if (widget.sending) {
      final now = state.txNow();
      tones = now == null || now.kind == ToneKind.silence
          ? const []
          : now.hz;
      headline = _range(tones);
      detail = switch (now?.kind) {
        null => 'Between bursts',
        ToneKind.silence => 'Gap between frames',
        ToneKind.marker => 'Sync marker · ${_count(tones)}',
        ToneKind.data => 'Data · ${_count(tones)}',
      };
    } else {
      final rx = state.rx;
      tones = rx.peaksHz;
      bands = rx.bands;
      headline = tones.isEmpty ? '—' : _format(tones.first);
      detail = tones.isEmpty
          ? 'No clear tone'
          : '${rx.peakDbfs!.round()} dBFS'
              '${tones.length > 1 ? ' · +${tones.length - 1} more tones' : ''}';
    }

    final label = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: Colors.white54, letterSpacing: 0.8);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.sending ? 'SENDING NOW' : 'HEARING NOW', style: label),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                headline,
                style: TextStyle(
                  color: tones.isEmpty ? Colors.white38 : accent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  detail,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpectrumStripPainter(
                tones: tones,
                bands: bands,
                accent: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _format(double hz) => hz >= 1000
      ? '${(hz / 1000).toStringAsFixed(2)} kHz'
      : '${hz.round()} Hz';

  static String _range(List<double> hz) {
    if (hz.isEmpty) return '—';
    if (hz.length == 1) return _format(hz.first);
    final lo = hz.reduce(math.min);
    final hi = hz.reduce(math.max);
    return '${(lo / 1000).toStringAsFixed(2)}–${_format(hi)}';
  }

  static String _count(List<double> hz) =>
      hz.length == 1 ? '1 tone' : '${hz.length} tones at once';
}

/// 0–22 kHz strip: the two sound bands shaded, received energy as bars and
/// the current tones as markers.
class _SpectrumStripPainter extends CustomPainter {
  _SpectrumStripPainter({
    required this.tones,
    required this.bands,
    required this.accent,
  });

  final List<double> tones;
  final Float32List? bands;
  final Color accent;

  static const _maxHz = 22050.0;
  static const _axisHeight = 14.0;

  static final Map<AcousticBand, (double, double)> _bandRanges = {
    for (final band in AcousticBand.values) band: _rangeOf(band),
  };

  static (double, double) _rangeOf(AcousticBand band) {
    var lo = double.infinity;
    var hi = 0.0;
    for (final profile in AcousticTxProfile.forBand(band)) {
      final codec = profile.buildCodec();
      lo = math.min(lo, codec.lowestHz);
      hi = math.max(hi, codec.highestHz);
    }
    return (lo, hi);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = size.height - _axisHeight;
    double x(double hz) => (hz / _maxHz).clamp(0.0, 1.0) * size.width;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, plotHeight),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.04),
    );

    for (final entry in _bandRanges.entries) {
      final (lo, hi) = entry.value;
      final color = entry.key == AcousticBand.audible
          ? Colors.amberAccent
          : Colors.tealAccent;
      canvas.drawRect(
        Rect.fromLTRB(x(lo), 0, x(hi), plotHeight),
        Paint()..color = color.withValues(alpha: 0.10),
      );
    }

    final levels = bands;
    if (levels != null && levels.isNotEmpty) {
      final barWidth = size.width / levels.length;
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.35);
      for (var i = 0; i < levels.length; i++) {
        final h = levels[i] * plotHeight;
        if (h < 0.5) continue;
        canvas.drawRect(
          Rect.fromLTWH(i * barWidth, plotHeight - h, barWidth * 0.8, h),
          paint,
        );
      }
    }

    final marker = Paint()
      ..color = accent
      ..strokeWidth = 2;
    for (final hz in tones) {
      final px = x(hz);
      canvas.drawLine(Offset(px, 0), Offset(px, plotHeight), marker);
    }

    final tick = Paint()..color = Colors.white24;
    for (var khz = 0; khz <= 20; khz += 5) {
      final px = x(khz * 1000.0);
      canvas.drawLine(
        Offset(px, plotHeight),
        Offset(px, plotHeight + 3),
        tick,
      );
      final text = TextPainter(
        text: TextSpan(
          text: khz == 0 ? '0' : '${khz}k',
          style: const TextStyle(color: Colors.white38, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (px - text.width / 2).clamp(0.0, size.width - text.width);
      text
        ..paint(canvas, Offset(left, plotHeight + 3))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_SpectrumStripPainter old) =>
      !identical(old.tones, tones) ||
      !identical(old.bands, bands) ||
      old.accent != accent;
}

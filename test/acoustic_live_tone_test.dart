import 'dart:math' as math;
import 'dart:typed_data';

import 'package:adaptive_physical_communication/core/chat/chat_payload_codec.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_fountain_modem.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/acoustic_tx_profile.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/spectrum_analyzer.dart';
import 'package:adaptive_physical_communication/core/physical/acoustic/tone_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _sines(List<double> hz, {int length = 4096, double amplitude = 0.3}) {
  final out = Float32List(length);
  for (final f in hz) {
    for (var i = 0; i < length; i++) {
      out[i] += amplitude / hz.length * math.sin(2 * math.pi * f * i / 44100);
    }
  }
  return out;
}

void main() {
  group('ToneTimeline', () {
    test('describes exactly the samples encode writes', () {
      final payload = Uint8List.fromList(List.generate(29, (i) => i * 37));
      for (final profile in [
        ...AcousticTxProfile.audibleValues,
        ...AcousticTxProfile.silentValues,
      ]) {
        final codec = profile.buildCodec();
        final tones = ToneTimeline(sampleRate: codec.sampleRate);
        codec.describe(payload, tones);
        expect(tones.totalSamples, codec.encode(payload).length,
            reason: profile.label);
        expect(tones.at(0)!.kind, ToneKind.marker, reason: profile.label);
        expect(tones.at(tones.totalSamples - 1)!.kind, ToneKind.data,
            reason: profile.label);
        expect(tones.at(tones.totalSamples), isNull);
      }
    });

    test('merges consecutive silences and looks up by time', () {
      final tones = ToneTimeline(sampleRate: 1000)
        ..addSilence(100)
        ..addSilence(50)
        ..addTones(200, ToneKind.data, [1000, 2000])
        ..addSilence(10);
      expect(tones.segmentCount, 3);
      expect(tones.totalSamples, 360);
      expect(tones.atTime(const Duration(milliseconds: 149))!.kind,
          ToneKind.silence);
      final mid = tones.atTime(const Duration(milliseconds: 200))!;
      expect(mid.kind, ToneKind.data);
      expect(mid.hz, [1000, 2000]);
      expect(tones.duration, const Duration(milliseconds: 360));
    });
  });

  group('modem onBurst', () {
    for (final profile in [AcousticTxProfile.standard, AcousticTxProfile.silent]) {
      test('timeline matches each ${profile.label} burst', () async {
        final modem = AcousticFountainModem(profile: profile);
        final codec = profile.buildCodec();
        ToneTimeline? latest;
        var bursts = 0;
        await modem.transmit(
          envelope: ChatPayloadCodec.encodeText('live tones'),
          maxSymbols: 4,
          onBurst: (tones) => latest = tones,
          play: (wav) async {
            bursts++;
            // 44-byte WAV header, 16-bit mono samples.
            expect(latest!.totalSamples, (wav.length - 44) ~/ 2);
          },
        );
        expect(bursts, greaterThan(0));

        final data = <double>{};
        for (var s = 0; s < latest!.totalSamples; s += 256) {
          final seg = latest!.at(s)!;
          if (seg.kind == ToneKind.data) {
            data.addAll(seg.hz);
            expect(seg.hz.length, profile.groups);
          }
          if (seg.kind == ToneKind.marker) {
            // Silent sends its two sync tones one after the other.
            expect(seg.hz.length, profile.isSilent ? 1 : 2);
          }
        }
        expect(data, isNotEmpty);
        for (final hz in data) {
          expect(hz, inInclusiveRange(codec.lowestHz, codec.highestHz));
        }
      });
    }
  });

  group('SpectrumAnalyzer', () {
    test('finds a silent-band tone within a few hertz', () {
      final analyzer = SpectrumAnalyzer()..add(_sines([18906]));
      final snap = analyzer.analyze();
      expect(snap.peaksHz, hasLength(1));
      expect(snap.strongestHz!, closeTo(18906, 8));
      expect(snap.peakDbfs!, greaterThan(-30));
    });

    test('resolves every tone of an audible chord', () {
      const chord = [1938.0, 2885.0, 3919.0, 5082.0];
      final analyzer = SpectrumAnalyzer()..add(_sines(chord));
      final found = analyzer.analyze().peaksHz.toList()..sort();
      expect(found, hasLength(chord.length));
      for (var i = 0; i < chord.length; i++) {
        expect(found[i], closeTo(chord[i], 12));
      }
    });

    test('reports nothing for silence and after reset', () {
      final analyzer = SpectrumAnalyzer();
      expect(analyzer.analyze().peaksHz, isEmpty);
      analyzer
        ..add(_sines([4000]))
        ..reset();
      expect(analyzer.analyze().peaksHz, isEmpty);
    });
  });
}

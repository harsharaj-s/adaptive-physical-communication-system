import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';
import 'package:adaptive_physical_communication/core/media/sample_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses title, type and size budget from the asset name', () {
    final s = SampleMedia.fromAssetPath('assets/samples/videos/how_qr_codes_work_140kb.mp4')!;
    expect(s.title, 'How QR codes work');
    expect(s.budgetKb, 140);
    expect(s.type, ChatMessageType.video);
    expect(s.mimeType, 'video/mp4');
    final w = SampleMedia.fromAssetPath('assets/samples/videos/speed_of_light_80kb.webm')!;
    expect(w.title, 'Speed of light');
    expect(w.mimeType, 'video/webm');
    expect(SampleMedia.fromAssetPath('assets/other/x.jpg'), isNull);
    expect(SampleMedia.fromAssetPath('assets/samples/notes.txt'), isNull);
  });

  test('bundled samples load and stay within their size budgets', () async {
    final samples = await loadSampleMediaCatalog();
    expect(samples.where((s) => s.type == ChatMessageType.image), isNotEmpty);
    expect(samples.where((s) => s.type == ChatMessageType.video), isNotEmpty);
    expect(samples.first.type, ChatMessageType.image);
    for (final s in samples) {
      final bytes = await s.load();
      expect(bytes, isNotEmpty, reason: s.assetPath);
      expect(bytes.length, lessThanOrEqualTo(s.budgetKb! * 1024), reason: s.assetPath);
    }
  });
}

import 'package:flutter/services.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';

/// Demo photos and videos bundled under `assets/samples/` (built by
/// `tool/make_sample_media.py`). Already transfer-sized, so they skip
/// recompression.
class SampleMedia {
  const SampleMedia({
    required this.assetPath,
    required this.type,
    required this.mimeType,
  });

  static const assetPrefix = 'assets/samples/';

  final String assetPath;
  final ChatMessageType type;
  final String mimeType;

  static final _budgetPattern = RegExp(r'^(\d+)kb$');

  /// File-name words that read better in another case.
  static const _displayWords = {'qr': 'QR'};

  String get fileName => assetPath.split('/').last;

  List<String> get _stemWords => fileName.split('.').first.split('_');

  /// `how_qr_codes_work_140kb.mp4` -> `How QR codes work`.
  String get title {
    final text = _stemWords
        .where((w) => !_budgetPattern.hasMatch(w))
        .map((w) => _displayWords[w] ?? w)
        .join(' ');
    return text.isEmpty ? fileName : text[0].toUpperCase() + text.substring(1);
  }

  /// Size budget encoded in the file name (`..._50kb.mp4` -> 50), if any.
  int? get budgetKb {
    for (final w in _stemWords) {
      final m = _budgetPattern.firstMatch(w);
      if (m != null) return int.parse(m.group(1)!);
    }
    return null;
  }

  Future<Uint8List> load([AssetBundle? bundle]) async {
    final data = await (bundle ?? rootBundle).load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static SampleMedia? fromAssetPath(String path) {
    if (!path.startsWith(assetPrefix)) return null;
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => SampleMedia(
          assetPath: path, type: ChatMessageType.image, mimeType: 'image/jpeg'),
      'png' => SampleMedia(
          assetPath: path, type: ChatMessageType.image, mimeType: 'image/png'),
      'mp4' => SampleMedia(
          assetPath: path, type: ChatMessageType.video, mimeType: 'video/mp4'),
      'webm' => SampleMedia(
          assetPath: path, type: ChatMessageType.video, mimeType: 'video/webm'),
      _ => null,
    };
  }
}

/// All bundled samples: images first, then by title and size budget.
Future<List<SampleMedia>> loadSampleMediaCatalog([AssetBundle? bundle]) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
  return manifest
      .listAssets()
      .map(SampleMedia.fromAssetPath)
      .whereType<SampleMedia>()
      .toList()
    ..sort((a, b) {
      final byType = a.type.index.compareTo(b.type.index);
      if (byType != 0) return byType;
      final byTitle = a.title.compareTo(b.title);
      if (byTitle != 0) return byTitle;
      return (a.budgetKb ?? 0).compareTo(b.budgetKb ?? 0);
    });
}

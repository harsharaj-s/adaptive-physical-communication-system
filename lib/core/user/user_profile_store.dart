import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local display-name storage. Kept short so on-air overhead stays tiny.
class UserProfileStore {
  UserProfileStore._();

  static const maxNameLength = 20;
  static const _fileName = 'display_name.txt';

  /// Trim, strip control characters, and clamp length.
  static String? sanitize(String? raw) {
    if (raw == null) return null;
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return null;
    return cleaned.length <= maxNameLength
        ? cleaned
        : cleaned.substring(0, maxNameLength);
  }

  static Future<File?> _file() async {
    try {
      final root = await getApplicationDocumentsDirectory();
      return File('${root.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      return sanitize(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<bool> save(String name) async {
    final cleaned = sanitize(name);
    if (cleaned == null) return false;
    try {
      final file = await _file();
      if (file == null) return false;
      await file.writeAsString(cleaned, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'package:adaptive_physical_communication/core/chat/chat_message.dart';

/// Saves received photos and videos to the phone gallery (album
/// [albumName]). Each message is saved at most once, so auto-save on receipt
/// and the manual button never create duplicates.
class GallerySaver extends ChangeNotifier {
  GallerySaver._();

  static final GallerySaver instance = GallerySaver._();

  static const albumName = 'Adaptive Comm';

  final Map<String, Future<bool>> _saves = {};
  final Set<String> _saved = {};
  final Map<String, String> _errors = {};

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool canSave(ChatMessage m) =>
      (m.type == ChatMessageType.image || m.type == ChatMessageType.video) &&
      (m.data?.isNotEmpty ?? false);

  bool isSaved(String id) => _saved.contains(id);

  bool isSaving(String id) => _saves.containsKey(id) && !_saved.contains(id);

  String? errorFor(String id) => _errors[id];

  Future<bool> save(ChatMessage m) {
    if (!isSupported || !canSave(m)) return Future.value(false);
    return _saves.putIfAbsent(m.id, () => _save(m));
  }

  Future<bool> _save(ChatMessage m) async {
    _errors.remove(m.id);
    notifyListeners();
    File? tmp;
    try {
      if (!await Gal.hasAccess(toAlbum: true) &&
          !await Gal.requestAccess(toAlbum: true)) {
        throw const _SaveFailure('Gallery permission denied');
      }
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
      tmp = File('${dir.path}/APC_${stamp.substring(0, 17)}.${_extension(m)}');
      await tmp.writeAsBytes(m.data!, flush: true);
      if (m.type == ChatMessageType.image) {
        await Gal.putImage(tmp.path, album: albumName);
      } else {
        await Gal.putVideo(tmp.path, album: albumName);
      }
      _saved.add(m.id);
      return true;
    } catch (e) {
      _saves.remove(m.id);
      _errors[m.id] = switch (e) {
        _SaveFailure(:final message) => message,
        GalException(:final type) => switch (type) {
            GalExceptionType.accessDenied => 'Gallery permission denied',
            GalExceptionType.notEnoughSpace => 'Not enough storage',
            GalExceptionType.notSupportedFormat => 'Format not supported by the gallery',
            GalExceptionType.unexpected => 'Could not save to gallery',
          },
        _ => 'Could not save to gallery',
      };
      return false;
    } finally {
      notifyListeners();
      tmp?.delete().ignore();
    }
  }

  static String _extension(ChatMessage m) {
    final fromName = m.fileName?.contains('.') == true
        ? m.fileName!.split('.').last.toLowerCase()
        : null;
    final mime = m.mimeType ?? '';
    if (m.type == ChatMessageType.image) {
      if (mime.contains('png') || fromName == 'png') return 'png';
      if (mime.contains('webp') || fromName == 'webp') return 'webp';
      if (mime.contains('gif') || fromName == 'gif') return 'gif';
      return 'jpg';
    }
    if (mime.contains('webm') || fromName == 'webm') return 'webm';
    if (mime.contains('quicktime') || fromName == 'mov') return 'mov';
    return 'mp4';
  }
}

class _SaveFailure implements Exception {
  const _SaveFailure(this.message);
  final String message;
}

import 'package:adaptive_physical_communication/core/types/types.dart';

typedef LogListener = void Function(LogEntry entry);

class StructuredLogger {
  StructuredLogger({this.maxEntries = 1000});

  final int maxEntries;
  final List<LogEntry> _entries = [];
  final List<LogListener> _listeners = [];

  void log(String category, String message, [Map<String, dynamic>? data]) {
    final entry = LogEntry(
      category: category,
      message: message,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      data: data,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeAt(0);
    for (final l in _listeners) {
      l(entry);
    }
  }

  void discovery(String message, [Map<String, dynamic>? data]) =>
      log('DISCOVERY', message, data);
  void info(String message, [Map<String, dynamic>? data]) =>
      log('INFO', message, data);
  void test(String message, [Map<String, dynamic>? data]) =>
      log('TEST', message, data);
  void decision(String message, [Map<String, dynamic>? data]) =>
      log('DECISION', message, data);
  void transfer(String message, [Map<String, dynamic>? data]) =>
      log('TRANSFER', message, data);
  void warning(String message, [Map<String, dynamic>? data]) =>
      log('WARNING', message, data);
  void adapt(String message, [Map<String, dynamic>? data]) =>
      log('ADAPT', message, data);
  void switchChannel(String message, [Map<String, dynamic>? data]) =>
      log('SWITCH', message, data);
  void error(String message, [Map<String, dynamic>? data]) =>
      log('ERROR', message, data);

  List<LogEntry> get entries => List.unmodifiable(_entries);
  void clear() => _entries.clear();

  void Function() onLog(LogListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

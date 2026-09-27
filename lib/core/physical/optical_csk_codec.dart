import 'dart:typed_data';
import 'dart:ui' show Color;

/// IEEE 802.15.7-inspired Color Shift Keying (CSK).
/// Each of 4 screen cells encodes 2 bits → one byte per color frame.
enum CskSymbol {
  red(0, Color(0xFFFF1414)),
  green(1, Color(0xFF14DC28)),
  blue(2, Color(0xFF1E50FF)),
  white(3, Color(0xFFFFFFFF));

  const CskSymbol(this.dibit, this.color);
  final int dibit;
  final Color color;
}

const cskPreambleBytes = [0x00, 0x55, 0xAA, 0xFF];

/// Max APCM envelope for one optical CSK burst (short text; color flashes are slow).
const hardwareOpticalCskMaxBytes = 180;

/// Color hold time per byte-frame (ms).
/// Increased for robust camera sampling on mid-range phones.
const hardwareOpticalCskSymbolMs = 140;

/// Black guard between frames so repeated bytes are separable.
const hardwareOpticalCskGuardMs = 20;

const hardwareOpticalCskLeadMs = 250;
const hardwareOpticalCskRepeatCount = 3;
const hardwareOpticalCskRepeatGapMs = 400;

class OpticalCskCodec {
  List<Color> cellsForByte(int byte) {
    return [
      CskSymbol.values[(byte >> 6) & 3].color,
      CskSymbol.values[(byte >> 4) & 3].color,
      CskSymbol.values[(byte >> 2) & 3].color,
      CskSymbol.values[byte & 3].color,
    ];
  }

  /// Preamble + 2-byte LE length + payload.
  Uint8List frameEnvelope(Uint8List envelope) {
    final out = Uint8List(cskPreambleBytes.length + 2 + envelope.length);
    out.setRange(0, 4, cskPreambleBytes);
    out[4] = envelope.length & 0xFF;
    out[5] = (envelope.length >> 8) & 0xFF;
    out.setRange(6, out.length, envelope);
    return out;
  }

  int classifyRgb(double r, double g, double b) {
    if (_isBlack(r, g, b)) return -1;
    var best = 0;
    var bestDist = double.infinity;
    for (final s in CskSymbol.values) {
      final argb = s.color.toARGB32();
      final sr = ((argb >> 16) & 0xFF).toDouble();
      final sg = ((argb >> 8) & 0xFF).toDouble();
      final sb = (argb & 0xFF).toDouble();
      final dr = r - sr;
      final dg = g - sg;
      final db = b - sb;
      final d = dr * dr + dg * dg + db * db;
      if (d < bestDist) {
        bestDist = d;
        best = s.dibit;
      }
    }
    return best;
  }

  bool _isBlack(double r, double g, double b) {
    final maxc = r > g ? (r > b ? r : b) : (g > b ? g : b);
    return maxc < 48;
  }

  /// Returns -1 for guard (black), otherwise packed byte, or null if mixed/unstable.
  int? packFrame(List<(double, double, double)> cells) {
    if (cells.length != 4) return null;
    var blackCount = 0;
    final dibits = <int>[];
    for (final cell in cells) {
      final d = classifyRgb(cell.$1, cell.$2, cell.$3);
      if (d < 0) {
        blackCount++;
        dibits.add(-1);
      } else {
        dibits.add(d);
      }
    }
    if (blackCount >= 3) return -1;
    if (dibits.any((d) => d < 0)) return null;
    return (dibits[0] << 6) | (dibits[1] << 4) | (dibits[2] << 2) | dibits[3];
  }
}

final opticalCskCodec = OpticalCskCodec();

/// Streaming CSK decoder with black-guard symbol separation.
class OpticalCskDecoder {
  final List<int> _bytes = [];
  int? _pending;
  int _pendingHits = 0;
  int? _lastCommitted;
  bool _afterGuard = true;

  (int received, int expected)? get progress {
    if (_bytes.length < cskPreambleBytes.length + 2) return null;
    if (!_preambleMatches()) return null;
    final total = _bytes[4] | (_bytes[5] << 8);
    if (total <= 0 || total > hardwareOpticalCskMaxBytes + 64) return null;
    final got = (_bytes.length - 6).clamp(0, total);
    return (got, total);
  }

  void noteGuard() {
    _afterGuard = true;
    _pending = null;
    _pendingHits = 0;
  }

  void addSampledByte(int byte) {
    if (!_afterGuard && byte == _lastCommitted) {
      _pending = byte;
      _pendingHits = 0;
      return;
    }
    if (_pending == byte) {
      _pendingHits++;
    } else {
      _pending = byte;
      _pendingHits = 1;
    }
    // One confirmed sample after guard is enough; TX timing already inserts
    // explicit guards, so requiring 2 identical hits can miss bytes on lower
    // camera frame rates.
    if (_pendingHits < 1) return;
    if (_lastCommitted == byte && !_afterGuard) return;
    _bytes.add(byte);
    _lastCommitted = byte;
    _afterGuard = false;
    _pendingHits = 0;
    _trim();
  }

  Uint8List? pollEnvelope({int maxPayloadBytes = hardwareOpticalCskMaxBytes}) {
    if (_bytes.length < cskPreambleBytes.length + 2) return null;
    final start = _findPreamble();
    if (start < 0) return null;
    if (_bytes.length < start + 6) return null;
    final len = _bytes[start + 4] | (_bytes[start + 5] << 8);
    if (len <= 0 || len > maxPayloadBytes) {
      _bytes.removeRange(0, start + 1);
      return null;
    }
    if (_bytes.length < start + 6 + len) return null;
    final payload = Uint8List.fromList(
      _bytes.sublist(start + 6, start + 6 + len),
    );
    _bytes.removeRange(0, start + 6 + len);
    _lastCommitted = null;
    return payload;
  }

  void reset() {
    _bytes.clear();
    _pending = null;
    _pendingHits = 0;
    _lastCommitted = null;
    _afterGuard = true;
  }

  bool _preambleMatches() {
    if (_bytes.length < 4) return false;
    for (var i = 0; i < 4; i++) {
      if (_bytes[i] != cskPreambleBytes[i]) return false;
    }
    return true;
  }

  int _findPreamble() {
    for (var i = 0; i <= _bytes.length - 4; i++) {
      var ok = true;
      for (var j = 0; j < 4; j++) {
        if (_bytes[i + j] != cskPreambleBytes[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  void _trim() {
    const max = 2048;
    if (_bytes.length > max) {
      _bytes.removeRange(0, _bytes.length - max ~/ 2);
    }
  }
}

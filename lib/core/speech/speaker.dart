import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../analytics/analytics.dart';

/// Reads words aloud with the system text-to-speech engine (offline when
/// the device has an English voice installed).
class Speaker {
  Speaker([FlutterTts? tts]) : _tts = tts;

  FlutterTts? _tts;
  bool _ready = false;

  Future<FlutterTts> _engine() async {
    final tts = _tts ??= FlutterTts();
    if (!_ready) {
      _ready = true;
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.42);
    }
    return tts;
  }

  /// Speaks [text]; returns false when no engine or voice is available.
  Future<bool> speak(String text, {required String surface}) async {
    Analytics.track('word_pronounce', {'word': text, 'surface': surface});
    try {
      final tts = await _engine();
      await tts.stop();
      final r = await tts.speak(text);
      return r == 1;
    } catch (e) {
      debugPrint('[tts] $e');
      return false;
    }
  }
}

final speakerProvider = Provider((ref) => Speaker());

// TODO PRI-58: Implementasi TTS output menggunakan flutter_tts
// Support Bahasa Indonesia
// Auto-play saat kondisi Red

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;

  Future<void> initialize() async {
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(0.9);
    await _tts.setVolume(1.0);
  }

  void toggle() => _isEnabled = !_isEnabled;

  Future<void> speak(String text) async {
    if (!_isEnabled) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}

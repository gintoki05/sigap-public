import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static const double defaultSpeechRate = 0.5;

  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isEnabled = false;
  bool _isInitialized = false;
  double _speechRate = defaultSpeechRate;

  bool get isEnabled => _isEnabled;
  double get speechRate => _speechRate;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(_speechRate);
    await _tts.setVolume(1.0);
    _isInitialized = true;
  }

  Future<bool> toggle() async {
    _isEnabled = !_isEnabled;
    if (!_isEnabled) {
      await stop();
    }
    return _isEnabled;
  }

  Future<void> speak(String text) async {
    if (!_isEnabled) return;
    if (!_isInitialized) {
      await initialize();
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<double> setSpeechRate(double value) async {
    final normalized = value.clamp(0.3, 0.8).toDouble();
    _speechRate = normalized;
    if (_isInitialized) {
      await _tts.setSpeechRate(_speechRate);
    }
    return _speechRate;
  }
}

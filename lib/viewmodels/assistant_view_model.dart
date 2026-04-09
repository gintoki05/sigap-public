import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../services/gemma_service.dart';

class AssistantMessage {
  const AssistantMessage({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;

  bool get isUser => role == 'user';

  AssistantMessage copyWith({
    String? role,
    String? text,
  }) {
    return AssistantMessage(
      role: role ?? this.role,
      text: text ?? this.text,
    );
  }
}

class AssistantViewModel extends ChangeNotifier {
  AssistantViewModel({
    required String inputMode,
    GemmaService? gemmaService,
    Connectivity? connectivity,
  })  : _inputMode = inputMode,
        _gemmaService = gemmaService ?? GemmaService(),
        _connectivity = connectivity ?? Connectivity() {
    _serviceStatus = _gemmaService.statusMessage;
  }

  final String _inputMode;
  final GemmaService _gemmaService;
  final Connectivity _connectivity;

  final List<AssistantMessage> _messages = [];
  final UrgencyLevel _urgency = UrgencyLevel.green;

  bool _ttsEnabled = false;
  bool? _isOnWifi;
  String _serviceStatus = 'Model Gemma belum diinisialisasi.';
  bool _isDisposed = false;
  final Map<SigapModelVariant, bool> _installedVariants = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  String get inputMode => _inputMode;
  List<AssistantMessage> get messages => List.unmodifiable(_messages);
  UrgencyLevel get urgency => _urgency;
  bool get ttsEnabled => _ttsEnabled;
  bool? get isOnWifi => _isOnWifi;
  String get serviceStatus => _serviceStatus;
  GemmaService get gemmaService => _gemmaService;
  Map<SigapModelVariant, bool> get installedVariants =>
      Map.unmodifiable(_installedVariants);

  bool get isModelReady => _gemmaService.isReady;
  bool get isDownloading => _gemmaService.isDownloading;
  bool get isDeleting => _gemmaService.isDeleting;
  int get downloadProgress => _gemmaService.downloadProgress;
  Duration? get downloadEta => _gemmaService.downloadEta;

  bool get isBusy {
    return _gemmaService.state == GemmaServiceState.initializing ||
        _gemmaService.state == GemmaServiceState.checking ||
        _gemmaService.state == GemmaServiceState.deleting;
  }

  Future<void> initialize() async {
    _gemmaService.addListener(_handleServiceUpdate);
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectivityState);
    await _refreshConnectivityState();
    await initializeReadyModel();
  }

  void toggleTts() {
    _ttsEnabled = !_ttsEnabled;
    notifyListeners();
  }

  Future<void> selectVariant(SigapModelVariant variant) async {
    await _gemmaService.selectModelVariant(variant);
    await initializeReadyModel();
  }

  Future<void> initializeReadyModel() async {
    _notifySafely();
    await _gemmaService.initializeReadyModel();
    await _refreshInstalledVariants();
    _serviceStatus = _gemmaService.statusMessage;
    _notifySafely();
  }

  Future<void> downloadModel() async {
    _notifySafely();
    await _gemmaService.downloadAndInstallModel();
    await _refreshInstalledVariants();
    _serviceStatus = _gemmaService.statusMessage;
    _notifySafely();
  }

  Future<void> deleteSelectedModel() async {
    _notifySafely();
    await _gemmaService.deleteSelectedModel();
    await _refreshInstalledVariants();
    _serviceStatus = _gemmaService.statusMessage;
    _notifySafely();
  }

  Future<void> cancelDownload() async {
    _notifySafely();
    await _gemmaService.cancelDownload();
    await _refreshInstalledVariants();
    _serviceStatus = _gemmaService.statusMessage;
    _notifySafely();
  }

  Future<void> importLocalModel() async {
    _notifySafely();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['litertlm', 'task', 'bin', 'tflite'],
        allowMultiple: false,
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        _serviceStatus = 'Impor model dibatalkan.';
        _notifySafely();
        return;
      }

      final pickedFile = result.files.single;
      final sourcePath = pickedFile.path;
      if (sourcePath == null || sourcePath.trim().isEmpty) {
        _serviceStatus =
            'File picker tidak memberikan path file yang bisa dibaca.';
        _notifySafely();
        return;
      }

      await _gemmaService.importSelectedModelFromPath(sourcePath);
      await _refreshInstalledVariants();
      _serviceStatus = _gemmaService.statusMessage;
      _notifySafely();
    } catch (error) {
      _serviceStatus = 'Gagal mengimpor model lokal: $error';
      _notifySafely();
    }
  }

  Future<bool> isSelectedModelInstalled() {
    return _gemmaService.isSelectedModelInstalled();
  }

  Future<void> sendMessage(String text) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return;
    }

    _messages.add(AssistantMessage(role: 'user', text: trimmedText));
    _messages.add(const AssistantMessage(role: 'assistant', text: ''));
    _notifySafely();

    if (!_gemmaService.isReady) {
      await _gemmaService.initializeReadyModel();
    }

    if (!_gemmaService.isReady) {
      _serviceStatus = _gemmaService.statusMessage;
      _replaceLastAssistantMessage(_serviceStatus);
      _notifySafely();
      return;
    }

    final buffer = StringBuffer();

    try {
      await for (final token in _gemmaService.generateResponse(trimmedText)) {
        buffer.write(token);
        _replaceLastAssistantMessage(buffer.toString());
        _notifySafely();
      }
      _serviceStatus = _gemmaService.statusMessage;
      _notifySafely();
    } catch (error) {
      final message = 'Terjadi kesalahan saat memproses pesan: $error';
      _replaceLastAssistantMessage(message);
      _serviceStatus = message;
      _notifySafely();
    }
  }

  void startVoice() {
    // TODO: Implement voice input via flutter_gemma audio
  }

  void pickPhoto() {
    // TODO: Implement image_picker + flutter_gemma vision
  }

  void sendEmergency() {
    // TODO: Implement geolocator + url_launcher WhatsApp
  }

  Future<void> _refreshConnectivityState() async {
    final results = await _connectivity.checkConnectivity();
    _updateConnectivityState(results);
  }

  Future<void> _refreshInstalledVariants() async {
    for (final variant in GemmaService.supportedVariants) {
      _installedVariants[variant] = await _gemmaService.isVariantInstalled(
        variant,
      );
    }
  }

  void _handleServiceUpdate() {
    _serviceStatus = _gemmaService.statusMessage;
    _notifySafely();
  }

  void _updateConnectivityState(List<ConnectivityResult> results) {
    final isOnWifi = results.contains(ConnectivityResult.wifi);
    if (_isOnWifi == isOnWifi) {
      return;
    }

    _isOnWifi = isOnWifi;
    _notifySafely();
  }

  void _replaceLastAssistantMessage(String text) {
    if (_messages.isEmpty) {
      return;
    }

    _messages[_messages.length - 1] = AssistantMessage(
      role: 'assistant',
      text: text,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _connectivitySubscription?.cancel();
    _gemmaService.removeListener(_handleServiceUpdate);
    super.dispose();
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }
}

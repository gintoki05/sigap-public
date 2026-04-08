import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';

enum GemmaServiceState {
  idle,
  checking,
  needsDownload,
  downloading,
  initializing,
  missingConfiguration,
  missingModelPath,
  missingModelFile,
  ready,
  error,
}

class GemmaService {
  GemmaService._internal();

  static final GemmaService _instance = GemmaService._internal();
  static const String modelPathEnvKey = 'SIGAP_GEMMA_MODEL_PATH';
  static const String modelUrlEnvKey = 'SIGAP_GEMMA_MODEL_URL';
  static const String modelAuthTokenEnvKey = 'SIGAP_GEMMA_MODEL_AUTH_TOKEN';
  static const String configuredModelPath =
      String.fromEnvironment(modelPathEnvKey);
  static const String configuredModelUrl = String.fromEnvironment(modelUrlEnvKey);
  static const String configuredModelAuthToken =
      String.fromEnvironment(modelAuthTokenEnvKey);

  factory GemmaService() => _instance;

  bool _pluginInitialized = false;
  bool _isBusy = false;
  GemmaServiceState _state = GemmaServiceState.idle;
  String _statusMessage = 'Model Gemma belum diinisialisasi.';
  int _downloadProgress = 0;
  InferenceModel? _model;
  InferenceChat? _chat;
  PreferredBackend? _activeBackend;

  GemmaServiceState get state => _state;
  String get statusMessage => _statusMessage;
  int get downloadProgress => _downloadProgress;
  bool get isReady => _state == GemmaServiceState.ready && _model != null;
  bool get isDownloading => _state == GemmaServiceState.downloading;
  bool get hasConfiguredLocalPath => configuredModelPath.trim().isNotEmpty;
  bool get hasConfiguredModelUrl => configuredModelUrl.trim().isNotEmpty;
  bool get needsDownload =>
      _state == GemmaServiceState.needsDownload ||
      _state == GemmaServiceState.missingConfiguration;
  bool get canRetry =>
      _state == GemmaServiceState.error ||
      _state == GemmaServiceState.missingModelFile ||
      _state == GemmaServiceState.missingModelPath ||
      _state == GemmaServiceState.missingConfiguration;
  PreferredBackend? get activeBackend => _activeBackend;
  String get estimatedModelSizeLabel => 'sekitar 4.3 GB';

  Future<void> initialize() async {
    await initializeReadyModel();
  }

  Future<void> initializeReadyModel() async {
    if (isReady || _isBusy) {
      return;
    }

    _isBusy = true;
    _state = GemmaServiceState.checking;
    _statusMessage = 'Memeriksa ketersediaan Gemma 4...';

    try {
      await _ensurePluginInitialized();

      if (FlutterGemma.hasActiveModel()) {
        await _loadActiveModel();
        return;
      }

      if (hasConfiguredLocalPath) {
        await _installFromLocalPath();
        if (_state == GemmaServiceState.missingModelFile ||
            _state == GemmaServiceState.missingModelPath) {
          return;
        }
        await _loadActiveModel();
        return;
      }

      if (!hasConfiguredModelUrl) {
        _downloadProgress = 0;
        _state = GemmaServiceState.missingConfiguration;
        _statusMessage =
            'URL model belum dikonfigurasi. Tambahkan --dart-define=$modelUrlEnvKey=https://.../gemma-4-e4b-it.litertlm atau gunakan path lokal untuk mode developer.';
        return;
      }

      if (await _isConfiguredNetworkModelInstalled()) {
        _state = GemmaServiceState.initializing;
        _statusMessage = 'Menyiapkan model Gemma yang sudah tersimpan...';
        await _installConfiguredNetworkModel(skipProgressUpdate: true);
        await _loadActiveModel();
        return;
      }

      _downloadProgress = 0;
      _state = GemmaServiceState.needsDownload;
      _statusMessage =
          'Model Gemma 4 belum ada di perangkat. Unduh sekali agar SIGAP bisa dipakai offline setelah setup awal.';
    } catch (error) {
      _state = GemmaServiceState.error;
      _statusMessage = 'Gagal menyiapkan Gemma 4: $error';
      await _releaseResources();
    } finally {
      _isBusy = false;
    }
  }

  Future<void> downloadAndInstallModel() async {
    if (_isBusy || isDownloading) {
      return;
    }

    await _ensurePluginInitialized();
    if (!hasConfiguredModelUrl) {
      _state = GemmaServiceState.missingConfiguration;
      _statusMessage =
          'Tidak ada URL model untuk diunduh. Tambahkan --dart-define=$modelUrlEnvKey=...';
      return;
    }

    _isBusy = true;
    _downloadProgress = 0;
    _state = GemmaServiceState.downloading;
    _statusMessage =
        'Mengunduh model Gemma 4. Proses ini hanya perlu sekali, lalu model akan tersimpan di perangkat.';

    try {
      await _installConfiguredNetworkModel();
      _state = GemmaServiceState.initializing;
      _statusMessage = 'Mengaktifkan model Gemma yang baru diunduh...';
      await _loadActiveModel();
    } catch (error) {
      _state = GemmaServiceState.error;
      _statusMessage = 'Gagal download atau install Gemma 4: $error';
      await _releaseResources();
    } finally {
      _isBusy = false;
    }
  }

  Stream<String> generateResponse(String prompt) async* {
    if (!isReady) {
      yield _statusMessage;
      return;
    }

    try {
      final chat = await _ensureChat();
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          yield response.token;
        }
      }
    } catch (error) {
      _state = GemmaServiceState.error;
      _statusMessage = 'Gagal menghasilkan respons Gemma: $error';
      yield _statusMessage;
    }
  }

  Future<void> resetConversation() async {
    if (_chat == null) {
      return;
    }
    await _chat!.close();
    _chat = null;
  }

  Future<void> dispose() async {
    await _releaseResources();
    _state = GemmaServiceState.idle;
    _statusMessage = 'Model Gemma belum diinisialisasi.';
    _downloadProgress = 0;
    _activeBackend = null;
  }

  Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) {
      return;
    }

    final authToken = configuredModelAuthToken.trim();
    await FlutterGemma.initialize(
      huggingFaceToken: authToken.isEmpty ? null : authToken,
    );
    _pluginInitialized = true;
  }

  Future<void> _installFromLocalPath() async {
    final configuredPath = configuredModelPath.trim();
    if (configuredPath.isEmpty) {
      _downloadProgress = 0;
      _state = GemmaServiceState.missingModelPath;
      _statusMessage =
          'Model lokal belum dikonfigurasi. Jalankan app dengan --dart-define=$modelPathEnvKey=/path/ke/model.litertlm.';
      return;
    }

    final file = File(configuredPath);
    if (!file.existsSync()) {
      _downloadProgress = 0;
      _state = GemmaServiceState.missingModelFile;
      _statusMessage =
          'File model lokal tidak ditemukan di $configuredPath. Pastikan file Gemma 4 E4B-IT sudah tersedia.';
      return;
    }

    _state = GemmaServiceState.initializing;
    _statusMessage = 'Memasang model lokal Gemma 4...';
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: _detectFileType(configuredPath),
    ).fromFile(configuredPath).install();
    _downloadProgress = 100;
  }

  Future<void> _loadActiveModel() async {
    _state = GemmaServiceState.initializing;
    _statusMessage = 'Menyiapkan sesi Gemma 4...';
    await _createModel();
    _state = GemmaServiceState.ready;
    _statusMessage = _activeBackend == PreferredBackend.gpu
        ? 'Gemma 4 siap dipakai offline dengan backend GPU.'
        : 'Gemma 4 siap dipakai offline dengan backend CPU.';
  }

  Future<void> _installConfiguredNetworkModel({
    bool skipProgressUpdate = false,
  }) async {
    final trimmedUrl = configuredModelUrl.trim();
    final trimmedToken = configuredModelAuthToken.trim();
    final builder = FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: _detectFileType(trimmedUrl),
    ).fromNetwork(
      trimmedUrl,
      token: trimmedToken.isEmpty ? null : trimmedToken,
    );

    if (!skipProgressUpdate) {
      builder.withProgress((progress) {
        _downloadProgress = progress;
        _state = GemmaServiceState.downloading;
        _statusMessage =
            'Mengunduh model Gemma 4... $progress% selesai. Setelah ini model akan tersimpan untuk pemakaian offline.';
      });
    }

    await builder.install();
    _downloadProgress = 100;
  }

  Future<bool> _isConfiguredNetworkModelInstalled() async {
    final modelUrl = configuredModelUrl.trim();
    if (modelUrl.isEmpty) {
      return false;
    }

    final modelId = Uri.parse(modelUrl).pathSegments.last;
    return FlutterGemma.isModelInstalled(modelId);
  }

  Future<void> _createModel() async {
    await _chat?.close();
    _chat = null;
    await _model?.close();
    _model = null;

    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.gpu,
      );
      _activeBackend = PreferredBackend.gpu;
    } catch (_) {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
      );
      _activeBackend = PreferredBackend.cpu;
    }
  }

  Future<InferenceChat> _ensureChat() async {
    if (_chat != null) {
      return _chat!;
    }

    final model = _model;
    if (model == null) {
      throw StateError('Model belum siap dipakai.');
    }

    _chat = await model.createChat(
      modelType: ModelType.gemmaIt,
      supportsFunctionCalls: false,
      isThinking: true,
      supportImage: false,
      supportAudio: false,
    );
    return _chat!;
  }

  Future<void> _releaseResources() async {
    if (_chat != null) {
      await _chat!.close();
      _chat = null;
    }
    if (_model != null) {
      await _model!.close();
      _model = null;
    }
  }

  ModelFileType _detectFileType(String filePath) {
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.litertlm')) {
      return ModelFileType.litertlm;
    }
    if (lowerPath.endsWith('.task')) {
      return ModelFileType.task;
    }
    if (lowerPath.endsWith('.bin') || lowerPath.endsWith('.tflite')) {
      return ModelFileType.binary;
    }
    throw UnsupportedError(
      'Format model tidak didukung: $filePath. Gunakan .litertlm, .task, .bin, atau .tflite.',
    );
  }
}

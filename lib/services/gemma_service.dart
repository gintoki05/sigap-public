import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';

enum GemmaServiceState {
  idle,
  checking,
  needsDownload,
  downloading,
  deleting,
  initializing,
  missingConfiguration,
  missingModelPath,
  missingModelFile,
  ready,
  error,
}

enum SigapModelVariant { e2b, e4b }

extension SigapModelVariantExtension on SigapModelVariant {
  String get label {
    switch (this) {
      case SigapModelVariant.e2b:
        return 'Gemma 4 E2B-IT';
      case SigapModelVariant.e4b:
        return 'Gemma 4 E4B-IT';
    }
  }

  String get estimatedSizeLabel {
    switch (this) {
      case SigapModelVariant.e2b:
        return 'sekitar 2.5 GB';
      case SigapModelVariant.e4b:
        return 'sekitar 4.3 GB';
    }
  }

  String get setupDescription {
    switch (this) {
      case SigapModelVariant.e2b:
        return 'Pilihan paling aman untuk setup awal. Download lebih ringan dan lebih ramah untuk device kelas menengah.';
      case SigapModelVariant.e4b:
        return 'Pilihan kualitas respons lebih tinggi. Cocok saat storage longgar dan device sudah siap menangani model besar.';
    }
  }

  bool get isRecommended => this == SigapModelVariant.e2b;

  String get bestForLabel {
    switch (this) {
      case SigapModelVariant.e2b:
        return 'Setup tercepat';
      case SigapModelVariant.e4b:
        return 'Respons lebih kaya';
    }
  }

  String get defaultUrl {
    switch (this) {
      case SigapModelVariant.e2b:
        return 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
      case SigapModelVariant.e4b:
        return 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm';
    }
  }
}

class GemmaService extends ChangeNotifier {
  GemmaService._internal();

  static final GemmaService _instance = GemmaService._internal();
  static const String modelPathEnvKey = 'SIGAP_GEMMA_MODEL_PATH';
  static const String modelUrlEnvKey = 'SIGAP_GEMMA_MODEL_URL';
  static const String modelAuthTokenEnvKey = 'SIGAP_GEMMA_MODEL_AUTH_TOKEN';
  static const List<SigapModelVariant> supportedVariants = [
    SigapModelVariant.e2b,
    SigapModelVariant.e4b,
  ];
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
  Duration? _downloadEta;
  DateTime? _lastProgressAt;
  int? _lastProgressValue;
  double? _smoothedProgressPerSecond;
  CancelToken? _downloadCancelToken;
  InferenceModel? _model;
  InferenceChat? _chat;
  PreferredBackend? _activeBackend;
  SigapModelVariant _selectedVariant = SigapModelVariant.e2b;

  GemmaServiceState get state => _state;
  String get statusMessage => _statusMessage;
  int get downloadProgress => _downloadProgress;
  Duration? get downloadEta => _downloadEta;
  bool get isReady => _state == GemmaServiceState.ready && _model != null;
  bool get isDownloading => _state == GemmaServiceState.downloading;
  bool get isDeleting => _state == GemmaServiceState.deleting;
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
  SigapModelVariant get selectedVariant => _selectedVariant;
  String get selectedModelLabel => _selectedVariant.label;
  String get estimatedModelSizeLabel => _selectedVariant.estimatedSizeLabel;
  String get selectedModelDescription => _selectedVariant.setupDescription;
  String get effectiveModelUrl =>
      configuredModelUrl.trim().isNotEmpty
          ? configuredModelUrl.trim()
          : _selectedVariant.defaultUrl;

  Future<void> initialize() async {
    await initializeReadyModel();
  }

  Future<void> selectModelVariant(SigapModelVariant variant) async {
    if (_selectedVariant == variant) {
      return;
    }

    await _releaseResources();
    _selectedVariant = variant;
    _activeBackend = null;
    _setState(
      GemmaServiceState.idle,
      '${variant.label} dipilih. ${variant.isRecommended ? 'Model ini direkomendasikan untuk mulai lebih cepat.' : 'Gunakan opsi ini bila Anda ingin kualitas respons lebih tinggi.'}',
      progress: 0,
    );
  }

  Future<void> initializeReadyModel() async {
    if (isReady || _isBusy) {
      return;
    }

    _isBusy = true;
    _setState(
      GemmaServiceState.checking,
      'Memeriksa ketersediaan ${_selectedVariant.label}...',
    );

    try {
      await _ensurePluginInitialized();

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
        _setState(
          GemmaServiceState.missingConfiguration,
          'URL model custom belum dikonfigurasi. SIGAP akan memakai default ${_selectedVariant.label} dari LiteRT Community.',
          progress: 0,
        );
      }

      if (await _isSelectedNetworkModelInstalled()) {
        _setState(
          GemmaServiceState.initializing,
          'Menyiapkan ${_selectedVariant.label} yang sudah tersimpan...',
        );
        await _installConfiguredNetworkModel(skipProgressUpdate: true);
        await _loadActiveModel();
        return;
      }

      _setState(
        GemmaServiceState.needsDownload,
        '${_selectedVariant.label} belum ada di perangkat. Unduh sekali agar SIGAP bisa dipakai offline setelah setup awal.',
        progress: 0,
      );
    } catch (error) {
      _setState(
        GemmaServiceState.error,
        'Gagal menyiapkan ${_selectedVariant.label}: $error',
      );
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
      _setState(
        GemmaServiceState.missingConfiguration,
        'URL custom tidak diberikan. SIGAP akan memakai default ${_selectedVariant.label}.',
      );
    }

    _isBusy = true;
    _downloadCancelToken = CancelToken();
    _resetDownloadEstimate();
    _setState(
      GemmaServiceState.downloading,
      'Mengunduh ${_selectedVariant.label}. Proses ini hanya perlu sekali, lalu model akan tersimpan di perangkat.',
      progress: 0,
    );

    try {
      await _installConfiguredNetworkModel();
      _setState(
        GemmaServiceState.initializing,
        'Mengaktifkan ${_selectedVariant.label} yang baru diunduh...',
        progress: 100,
      );
      await _loadActiveModel();
    } catch (error) {
      if (CancelToken.isCancel(error)) {
        _setState(
          GemmaServiceState.needsDownload,
          'Download ${_selectedVariant.label} dibatalkan. Anda bisa melanjutkan lagi kapan saja saat sudah siap.',
          progress: 0,
        );
        return;
      }

      _setState(
        GemmaServiceState.error,
        'Gagal download atau install ${_selectedVariant.label}: $error',
      );
      await _releaseResources();
    } finally {
      _downloadCancelToken = null;
      _resetDownloadEstimate();
      _isBusy = false;
    }
  }

  Future<void> cancelDownload() async {
    final cancelToken = _downloadCancelToken;
    if (!isDownloading || cancelToken == null || cancelToken.isCancelled) {
      return;
    }

    _setState(
      GemmaServiceState.downloading,
      'Membatalkan download ${_selectedVariant.label}...',
      progress: _downloadProgress,
    );
    cancelToken.cancel('User cancelled model download');
  }

  Future<bool> isSelectedModelInstalled() async {
    return isVariantInstalled(_selectedVariant);
  }

  Future<bool> isVariantInstalled(SigapModelVariant variant) async {
    await _ensurePluginInitialized();
    if (hasConfiguredLocalPath) {
      return File(configuredModelPath.trim()).existsSync();
    }

    final manager = FlutterGemmaPlugin.instance.modelManager;
    return manager.isModelInstalled(_buildModelSpec(variant));
  }

  Future<void> deleteSelectedModel() async {
    if (_isBusy) {
      return;
    }

    await _ensurePluginInitialized();

    if (hasConfiguredLocalPath) {
      _setState(
        GemmaServiceState.error,
        'Model file lokal dikelola di luar aplikasi. Hapus file tersebut langsung dari penyimpanan perangkat.',
      );
      return;
    }

    _isBusy = true;
    _setState(
      GemmaServiceState.deleting,
      'Menghapus ${_selectedVariant.label} dari perangkat...',
      progress: 0,
    );

    try {
      await _releaseResources();
      await FlutterGemmaPlugin.instance.modelManager.deleteModel(
        _buildSelectedModelSpec(),
      );
      _activeBackend = null;
      _setState(
        GemmaServiceState.needsDownload,
        '${_selectedVariant.label} telah dihapus. Unduh lagi bila ingin memakai model ini secara offline.',
        progress: 0,
      );
    } catch (error) {
      _setState(
        GemmaServiceState.error,
        'Gagal menghapus ${_selectedVariant.label}: $error',
      );
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
      _setState(
        GemmaServiceState.error,
        'Gagal menghasilkan respons ${_selectedVariant.label}: $error',
      );
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

  Future<void> reset() async {
    await _releaseResources();
    _activeBackend = null;
    _setState(
      GemmaServiceState.idle,
      'Model Gemma belum diinisialisasi.',
      progress: 0,
    );
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
      _setState(
        GemmaServiceState.missingModelPath,
        'Model lokal belum dikonfigurasi. Jalankan app dengan --dart-define=$modelPathEnvKey=/path/ke/model.litertlm.',
        progress: 0,
      );
      return;
    }

    final file = File(configuredPath);
    if (!file.existsSync()) {
      _setState(
        GemmaServiceState.missingModelFile,
        'File model lokal tidak ditemukan di $configuredPath. Pastikan file .litertlm sudah tersedia di storage Android/device, bukan hanya di host Windows.',
        progress: 0,
      );
      return;
    }

    _setState(
      GemmaServiceState.initializing,
      'Memasang model lokal dari file device...',
    );
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: _detectFileType(configuredPath),
    ).fromFile(configuredPath).install();
    _setState(
      GemmaServiceState.initializing,
      'Memasang model lokal dari file device...',
      progress: 100,
    );
  }

  Future<void> _loadActiveModel() async {
    _setState(
      GemmaServiceState.initializing,
      'Menyiapkan sesi ${_selectedVariant.label}...',
    );
    await _createModel();
    _setState(
      GemmaServiceState.ready,
      _activeBackend == PreferredBackend.gpu
          ? '${_selectedVariant.label} siap dipakai offline dengan backend GPU.'
          : '${_selectedVariant.label} siap dipakai offline dengan backend CPU.',
    );
  }

  Future<void> _installConfiguredNetworkModel({
    bool skipProgressUpdate = false,
  }) async {
    final trimmedUrl = effectiveModelUrl;
    final trimmedToken = configuredModelAuthToken.trim();
    final cancelToken = _downloadCancelToken;
    final builder = FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: _detectFileType(trimmedUrl),
    ).fromNetwork(
      trimmedUrl,
      token: trimmedToken.isEmpty ? null : trimmedToken,
    );

    if (cancelToken != null) {
      builder.withCancelToken(cancelToken);
    }

    if (!skipProgressUpdate) {
      builder.withProgress((progress) {
        _updateDownloadEstimate(progress);
        _setState(
          GemmaServiceState.downloading,
          'Mengunduh ${_selectedVariant.label}... $progress% selesai. Setelah ini model akan tersimpan untuk pemakaian offline.',
          progress: progress,
        );
      });
    }

    await builder.install();
    _downloadEta = Duration.zero;
    _setState(
      GemmaServiceState.downloading,
      'Mengunduh ${_selectedVariant.label}... 100% selesai. Setelah ini model akan tersimpan untuk pemakaian offline.',
      progress: 100,
    );
  }

  Future<bool> _isSelectedNetworkModelInstalled() async {
    return isSelectedModelInstalled();
  }

  InferenceModelSpec _buildSelectedModelSpec() {
    return _buildModelSpec(_selectedVariant);
  }

  InferenceModelSpec _buildModelSpec(SigapModelVariant variant) {
    final modelUrl = configuredModelUrl.trim().isNotEmpty
        ? configuredModelUrl.trim()
        : variant.defaultUrl;
    final modelName = Uri.parse(modelUrl).pathSegments.last.split('.').first;
    return MobileModelManager.createInferenceSpec(
      name: modelName,
      modelUrl: modelUrl,
    );
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

  void _setState(
    GemmaServiceState newState,
    String newStatus, {
    int? progress,
  }) {
    final didChange = _state != newState ||
        _statusMessage != newStatus ||
        (progress != null && _downloadProgress != progress);

    _state = newState;
    _statusMessage = newStatus;
    if (progress != null) {
      _downloadProgress = progress.clamp(0, 100).toInt();
    }

    if (didChange) {
      notifyListeners();
    }
  }

  void _updateDownloadEstimate(int progress) {
    final now = DateTime.now();
    if (_lastProgressAt == null || _lastProgressValue == null) {
      _lastProgressAt = now;
      _lastProgressValue = progress;
      return;
    }

    final seconds = now.difference(_lastProgressAt!).inMilliseconds / 1000;
    final progressDelta = progress - _lastProgressValue!;
    if (seconds <= 0 || progressDelta <= 0) {
      return;
    }

    final instantaneousRate = progressDelta / seconds;
    _smoothedProgressPerSecond = _smoothedProgressPerSecond == null
        ? instantaneousRate
        : (_smoothedProgressPerSecond! * 0.7) + (instantaneousRate * 0.3);

    if (_smoothedProgressPerSecond != null && _smoothedProgressPerSecond! > 0) {
      final remainingProgress = 100 - progress;
      final remainingSeconds = remainingProgress / _smoothedProgressPerSecond!;
      if (remainingSeconds.isFinite && remainingSeconds > 0) {
        _downloadEta = Duration(seconds: remainingSeconds.round());
      }
    }

    _lastProgressAt = now;
    _lastProgressValue = progress;
  }

  void _resetDownloadEstimate() {
    _downloadEta = null;
    _lastProgressAt = null;
    _lastProgressValue = null;
    _smoothedProgressPerSecond = null;
  }
}

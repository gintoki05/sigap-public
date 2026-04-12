import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../services/gemma_service.dart';
import '../services/rag_service.dart';
import '../services/tts_service.dart';

class AssistantGuidanceStep {
  const AssistantGuidanceStep({required this.title, required this.details});

  final String title;
  final String details;
}

class AssistantGuidance {
  const AssistantGuidance({
    required this.urgency,
    required this.summary,
    required this.warning,
    required this.steps,
    required this.followUpQuestions,
    required this.rawText,
  });

  final UrgencyLevel urgency;
  final String summary;
  final String warning;
  final List<AssistantGuidanceStep> steps;
  final List<String> followUpQuestions;
  final String rawText;
}

class AssistantMessage {
  const AssistantMessage({
    required this.role,
    required this.text,
    this.guidance,
    this.photoBytes,
    this.photoName,
  });

  final String role;
  final String text;
  final AssistantGuidance? guidance;
  final Uint8List? photoBytes;
  final String? photoName;

  bool get isUser => role == 'user';
  bool get hasStructuredGuidance => guidance != null;
  bool get hasPhoto => photoBytes != null;

  AssistantMessage copyWith({
    String? role,
    String? text,
    AssistantGuidance? guidance,
    Uint8List? photoBytes,
    String? photoName,
  }) {
    return AssistantMessage(
      role: role ?? this.role,
      text: text ?? this.text,
      guidance: guidance ?? this.guidance,
      photoBytes: photoBytes ?? this.photoBytes,
      photoName: photoName ?? this.photoName,
    );
  }
}

class AssistantPhotoAttachment {
  const AssistantPhotoAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

enum AssistantVisionState {
  disabled,
  enabled,
  tryingVision,
  visionFailedFallback,
}

class AssistantGuidanceRequest {
  const AssistantGuidanceRequest({
    required this.userMessage,
    required this.fallbackInput,
    required this.ragQuery,
    this.includePhotoContext = false,
    this.hasPhotoAttachmentWithoutVision = false,
    this.includeAudioContext = false,
    this.userPhotoBytes,
    this.userPhotoName,
    this.userAudioBytes,
  });

  final String userMessage;
  final String fallbackInput;
  final String ragQuery;
  final bool includePhotoContext;
  final bool hasPhotoAttachmentWithoutVision;
  final bool includeAudioContext;
  final Uint8List? userPhotoBytes;
  final String? userPhotoName;
  final Uint8List? userAudioBytes;

  bool get usesImageInference => includePhotoContext && userPhotoBytes != null;
  bool get usesAudioInference => includeAudioContext && userAudioBytes != null;
}

class EmergencyLaunchResult {
  const EmergencyLaunchResult({
    required this.isSuccess,
    required this.message,
    this.requiresContact = false,
  });

  final bool isSuccess;
  final String message;
  final bool requiresContact;
}

class AssistantViewModel extends ChangeNotifier {
  static const String _emergencyContactNameKey = 'sigap.emergency_contact_name';
  static const String _emergencyContactPhoneKey =
      'sigap.emergency_contact_phone';
  static const String _visionBetaEnabledKey = 'sigap.vision_beta_enabled';
  static const Duration _maxVoiceRecordingDuration = Duration(seconds: 20);

  AssistantViewModel({
    required String inputMode,
    GemmaService? gemmaService,
    Connectivity? connectivity,
    RagService? ragService,
    TtsService? ttsService,
  }) : _inputMode = inputMode,
       _gemmaService = gemmaService ?? GemmaService(),
       _ragService = ragService ?? RagService(),
       _ttsService = ttsService ?? TtsService(),
       _connectivity = connectivity ?? Connectivity() {
    _serviceStatus = _gemmaService.statusMessage;
  }

  String _inputMode;
  final GemmaService _gemmaService;
  final RagService _ragService;
  final TtsService _ttsService;
  final Connectivity _connectivity;
  final AudioRecorder _audioRecorder = AudioRecorder();

  final List<AssistantMessage> _messages = [];
  UrgencyLevel _urgency = UrgencyLevel.green;

  bool _ttsEnabled = false;
  double _ttsSpeechRate = TtsService.defaultSpeechRate;
  bool? _isOnWifi;
  String _serviceStatus = 'Model Gemma belum diinisialisasi.';
  String? _emergencyContactName;
  String? _emergencyContactPhone;
  bool _isDisposed = false;
  bool _isImportingLocalModel = false;
  bool _isSendingMessage = false;
  bool _isSendingEmergency = false;
  bool _isRecordingVoice = false;
  bool _isVisionBetaEnabled = false;
  bool _isStoppingGeneration = false;
  bool _stopGenerationRequested = false;
  Duration _voiceRecordingDuration = Duration.zero;
  Timer? _voiceRecordingTimer;
  String? _voiceRecordingPath;
  AssistantVisionState _visionState = AssistantVisionState.disabled;
  AssistantGuidanceRequest? _lastGuidanceRequest;
  int? _lastAssistantResponseIndex;
  final Map<SigapModelVariant, bool> _installedVariants = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  String get inputMode => _inputMode;
  List<AssistantMessage> get messages => List.unmodifiable(_messages);
  UrgencyLevel get urgency => _urgency;
  bool get ttsEnabled => _ttsEnabled;
  double get ttsSpeechRate => _ttsSpeechRate;
  bool? get isOnWifi => _isOnWifi;
  String get serviceStatus => _serviceStatus;
  GemmaService get gemmaService => _gemmaService;
  String? get emergencyContactName => _emergencyContactName;
  String? get emergencyContactPhone => _emergencyContactPhone;
  Map<SigapModelVariant, bool> get installedVariants =>
      Map.unmodifiable(_installedVariants);
  bool get isVisionBetaEnabled => _isVisionBetaEnabled;
  AssistantVisionState get visionState => _visionState;
  bool get isTryingVision => _visionState == AssistantVisionState.tryingVision;
  String get visionStatusSummary {
    switch (_visionState) {
      case AssistantVisionState.disabled:
        return 'AI Vision (Hemat RAM) dimatikan. SIGAP fokus pada deskripsi teks saat ada lampiran foto.';
      case AssistantVisionState.enabled:
        return _gemmaService.lastInferenceUsedVision
            ? _gemmaService.lastInferenceDebugLabel
            : 'AI Vision aktif memproses offline. Mohon tambahkan teks deskripsi sebagai fallback jika perangkat kehabisan RAM.';
      case AssistantVisionState.tryingVision:
        return 'Memproses gambar offline (Heavy Vision)... Prioritas beralih ke teks jika memori tidak cukup.';
      case AssistantVisionState.visionFailedFallback:
        return 'Memori perangkat tidak cukup untuk AI Vision. SIGAP beralih memakai deskripsi teks.';
    }
  }

  bool get isModelReady =>
      _gemmaService.isReady || _gemmaService.hasLoadedModelSuccessfully;
  bool get isDownloading => _gemmaService.isDownloading;
  bool get isDeleting => _gemmaService.isDeleting;
  int get downloadProgress => _gemmaService.downloadProgress;
  Duration? get downloadEta => _gemmaService.downloadEta;
  bool get isImportingLocalModel => _isImportingLocalModel;
  bool get isSendingEmergency => _isSendingEmergency;
  bool get isGeneratingResponse => _isSendingMessage;
  bool get isStoppingGeneration => _isStoppingGeneration;
  bool get isRecordingVoice => _isRecordingVoice;
  Duration get voiceRecordingDuration => _voiceRecordingDuration;
  bool get canStartNewSession =>
      !_isSendingMessage &&
      !_isSendingEmergency &&
      !_isRecordingVoice &&
      !_isImportingLocalModel &&
      !isDownloading &&
      !isDeleting;
  bool get hasEmergencyContact =>
      (_emergencyContactName?.trim().isNotEmpty ?? false) &&
      (_emergencyContactPhone?.trim().isNotEmpty ?? false);
  bool get canRegenerateLatestResponse =>
      !_isSendingMessage &&
      _lastGuidanceRequest != null &&
      _lastAssistantResponseIndex != null &&
      _lastAssistantResponseIndex == _messages.length - 1 &&
      _messages.isNotEmpty &&
      !_messages.last.isUser;

  bool get isBusy {
    return _isImportingLocalModel ||
        _isSendingMessage ||
        _isSendingEmergency ||
        _gemmaService.state == GemmaServiceState.initializing ||
        _gemmaService.state == GemmaServiceState.checking ||
        _gemmaService.state == GemmaServiceState.deleting;
  }

  Future<void> initialize() async {
    _gemmaService.addListener(_handleServiceUpdate);
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivityState,
    );
    await _refreshConnectivityState();
    await _loadEmergencyContact();
    await _loadVisionBetaPreference();
    await _ragService.initialize();
    await _initializeTts();
    await _refreshInstalledVariants();
    _notifySafely();
    await initializeReadyModel();
  }

  Future<void> toggleTts() async {
    final isEnabled = await _ttsService.toggle();
    _ttsEnabled = isEnabled;
    _notifySafely();

    if (isEnabled) {
      await _speakLatestGuidanceIfAvailable();
    }
  }

  void setInputMode(String value) {
    if (_inputMode == value) {
      return;
    }
    _inputMode = value;
    _notifySafely();
  }

  Future<void> setTtsSpeechRate(double value) async {
    try {
      _ttsSpeechRate = await _ttsService.setSpeechRate(value);
      _notifySafely();
    } catch (error) {
      _serviceStatus = 'Kecepatan suara gagal diubah: $error';
      _notifySafely();
    }
  }

  Future<void> replayGuidance(AssistantGuidance guidance) async {
    if (!_ttsEnabled) {
      _ttsEnabled = await _ttsService.toggle();
      _notifySafely();
    }
    await _speakGuidance(guidance);
  }

  Future<void> startNewSession() async {
    if (!canStartNewSession) {
      return;
    }

    await _ttsService.stop();
    await _gemmaService.resetConversation();

    _messages.clear();
    _urgency = UrgencyLevel.green;
    _lastGuidanceRequest = null;
    _lastAssistantResponseIndex = null;
    _isStoppingGeneration = false;
    _stopGenerationRequested = false;
    _serviceStatus =
        'Sesi baru dimulai. Jelaskan kondisi korban saat ini agar SIGAP bisa membantu.';
    _notifySafely();
  }

  Future<void> saveEmergencyContact({
    required String name,
    required String phone,
  }) async {
    final sanitizedName = name.trim();
    final sanitizedPhone = phone.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emergencyContactNameKey, sanitizedName);
    await prefs.setString(_emergencyContactPhoneKey, sanitizedPhone);
    _emergencyContactName = sanitizedName;
    _emergencyContactPhone = sanitizedPhone;
    _notifySafely();
  }

  Future<void> setVisionBetaEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_visionBetaEnabledKey, value);
    _isVisionBetaEnabled = value;
    _visionState = value
        ? AssistantVisionState.enabled
        : AssistantVisionState.disabled;
    _serviceStatus = value
        ? 'AI Vision aktif (Membutuhkan RAM besar). Processing berjalan secara on-device. Fallback teks akan dipakai bila memori RAM penuh.'
        : 'AI Vision dimatikan. Pemrosesan lebih hemat daya karena hanya mengandalkan deskripsi teks yang dilampirkan.';
    _notifySafely();
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
    if (_isImportingLocalModel) {
      return;
    }

    _isImportingLocalModel = true;
    _serviceStatus = 'Membuka pemilih file model...';
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

      _serviceStatus =
          'File dipilih. Menyalin ${_gemmaService.selectedModelLabel} ke penyimpanan aplikasi...';
      _notifySafely();
      await _gemmaService.importSelectedModelFromPath(sourcePath);
      await _refreshInstalledVariants();
      _serviceStatus = _gemmaService.statusMessage;
      _notifySafely();
    } catch (error) {
      _serviceStatus = 'Gagal mengimpor model lokal: $error';
      _notifySafely();
    } finally {
      _isImportingLocalModel = false;
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

    await _sendGuidanceRequest(
      userMessage: trimmedText,
      fallbackInput: trimmedText,
      ragQuery: trimmedText,
    );
  }

  Future<void> startVoice() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecordingAndSend();
      return;
    }

    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (_isSendingMessage || !_gemmaService.isReady) {
      _serviceStatus =
          'Model masih sibuk atau belum siap. Tunggu sampai Gemma siap sebelum merekam suara.';
      _notifySafely();
      return;
    }

    try {
      final microphoneStatus = await Permission.microphone.request();
      if (!microphoneStatus.isGranted) {
        _serviceStatus =
            'Izin mikrofon belum diberikan. Aktifkan izin mikrofon untuk mencoba input suara.';
        _notifySafely();
        return;
      }

      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _serviceStatus =
            'Izin mikrofon belum diberikan. Aktifkan izin mikrofon untuk mencoba input suara.';
        _notifySafely();
        return;
      }

      final tempDirectory = await getTemporaryDirectory();
      final path =
          '${tempDirectory.path}${Platform.pathSeparator}sigap_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: path,
      );

      _voiceRecordingPath = path;
      _voiceRecordingDuration = Duration.zero;
      _isRecordingVoice = true;
      _serviceStatus =
          'Merekam suara... tekan tombol mikrofon lagi untuk mengirim. Maksimal 20 detik.';
      _voiceRecordingTimer?.cancel();
      _voiceRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _voiceRecordingDuration += const Duration(seconds: 1);
        if (_voiceRecordingDuration >= _maxVoiceRecordingDuration) {
          unawaited(_stopVoiceRecordingAndSend());
          return;
        }
        _notifySafely();
      });
      _notifySafely();
    } catch (error) {
      _isRecordingVoice = false;
      _voiceRecordingDuration = Duration.zero;
      _voiceRecordingPath = null;
      _serviceStatus = 'Gagal mulai merekam suara: $error';
      _notifySafely();
    }
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (!_isRecordingVoice) {
      return;
    }

    _voiceRecordingTimer?.cancel();
    _voiceRecordingTimer = null;

    String? path;
    try {
      path = await _audioRecorder.stop();
      _isRecordingVoice = false;
      _serviceStatus = 'Rekaman suara selesai. SIGAP mencoba memahami audio...';
      _notifySafely();

      final effectivePath = path ?? _voiceRecordingPath;
      if (effectivePath == null || effectivePath.trim().isEmpty) {
        _serviceStatus = 'Rekaman suara tidak menghasilkan file audio.';
        _notifySafely();
        return;
      }

      final file = File(effectivePath);
      if (!file.existsSync()) {
        _serviceStatus = 'File rekaman suara tidak ditemukan.';
        _notifySafely();
        return;
      }

      final audioBytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {
        // Temporary recording cleanup failure should not block guidance.
      }

      if (audioBytes.isEmpty) {
        _serviceStatus = 'Rekaman suara kosong. Coba rekam ulang lebih dekat.';
        _notifySafely();
        return;
      }

      await sendVoiceMessage(
        audioBytes: audioBytes,
        duration: _voiceRecordingDuration,
      );
    } catch (error) {
      _isRecordingVoice = false;
      _serviceStatus =
          'Input suara beta gagal. Coba pakai chat teks dulu. Detail: $error';
      _notifySafely();
    } finally {
      _voiceRecordingPath = null;
      _voiceRecordingDuration = Duration.zero;
      _notifySafely();
    }
  }

  Future<void> sendVoiceMessage({
    required Uint8List audioBytes,
    Duration? duration,
  }) async {
    final durationLabel = _formatRecordingDuration(duration);
    await _sendGuidanceRequest(
      userMessage: durationLabel == null
          ? 'Saya mengirim rekaman suara kondisi darurat.'
          : 'Saya mengirim rekaman suara kondisi darurat ($durationLabel).',
      fallbackInput:
          'User mengirim rekaman suara berbahasa Indonesia tentang kondisi pertolongan pertama. Dengarkan audio dan susun panduan P3K yang aman. Jika audio tidak jelas, minta user mengulangi atau menulis lewat chat.',
      ragQuery: 'rekaman suara kondisi darurat pertolongan pertama',
      includeAudioContext: true,
      userAudioBytes: audioBytes,
    );
  }

  Future<AssistantPhotoAttachment?> capturePhoto() async {
    if (_isSendingMessage) {
      return null;
    }

    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        _serviceStatus = 'Pengambilan foto dibatalkan.';
        _notifySafely();
        return null;
      }

      final imageBytes = await pickedFile.readAsBytes();
      return AssistantPhotoAttachment(name: pickedFile.name, bytes: imageBytes);
    } catch (error) {
      _serviceStatus = 'Gagal mengambil foto kondisi: $error';
      _notifySafely();
      return null;
    }
  }

  Future<void> sendPhotoMessage({
    required Uint8List imageBytes,
    String? photoName,
    String text = '',
  }) async {
    final trimmedDraft = text.trim();

    if (!_isVisionBetaEnabled) {
      _visionState = AssistantVisionState.disabled;
      _serviceStatus =
          'Foto diterima, Mode AI Vision sedang dimatikan untuk hemat RAM. SIGAP memakai teks untuk stabilitas memori.';

      if (trimmedDraft.isEmpty) {
        _messages.add(
          AssistantMessage(
            role: 'user',
            text: 'Saya melampirkan foto kondisi.',
            photoBytes: imageBytes,
            photoName: photoName,
          ),
        );
        _messages.add(
          const AssistantMessage(
            role: 'assistant',
            text:
                'AI Vision dimatikan. Harap tambahkan deskripsi teks detail tentang lokasi, pendarahan, atau ukuran luka, agar SIGAP bisa membuat panduan P3K akurat.',
          ),
        );
        _notifySafely();
        return;
      }

      await _sendGuidanceRequest(
        userMessage: 'Saya mengirim foto kondisi. Catatan: $trimmedDraft',
        fallbackInput: trimmedDraft,
        ragQuery: trimmedDraft,
        hasPhotoAttachmentWithoutVision: true,
        userPhotoBytes: imageBytes,
        userPhotoName: photoName,
      );
      return;
    }

    _visionState = AssistantVisionState.tryingVision;
    _serviceStatus =
        'Memeriksa memori: Memulai AI Vision... SIGAP memproses gambar secara offline (Heavy RAM Mode). Jika nge-lag atau freeze, akan fallback ke deskripsi Anda.';
    _notifySafely();

    final userMessage = trimmedDraft.isEmpty
        ? 'Saya mengirim foto luka/kondisi untuk dianalisis.'
        : 'Saya mengirim foto luka/kondisi. Catatan: $trimmedDraft';
    final fallbackInput = trimmedDraft.isEmpty
        ? 'User melampirkan foto luka atau kondisi P3K dari kamera tanpa deskripsi teks tambahan.'
        : trimmedDraft;

    await _sendGuidanceRequest(
      userMessage: userMessage,
      fallbackInput: fallbackInput,
      ragQuery: trimmedDraft.isEmpty
          ? 'analisis foto luka pertolongan pertama'
          : trimmedDraft,
      includePhotoContext: true,
      userPhotoBytes: imageBytes,
      userPhotoName: photoName,
    );
  }

  Future<void> regenerateLatestResponse() async {
    final request = _lastGuidanceRequest;
    final assistantIndex = _lastAssistantResponseIndex;
    if (request == null ||
        assistantIndex == null ||
        _isSendingMessage ||
        assistantIndex < 0 ||
        assistantIndex >= _messages.length ||
        _messages[assistantIndex].isUser) {
      return;
    }

    _replaceAssistantMessageAt(assistantIndex, '');
    _serviceStatus = 'Menyusun ulang respons terakhir...';
    _isSendingMessage = true;
    _notifySafely();

    try {
      await _gemmaService.resetConversation();
    } catch (error) {
      final message = 'Gagal mereset sesi percakapan untuk regenerate: $error';
      _replaceAssistantMessageAt(assistantIndex, message);
      _serviceStatus = message;
      _isSendingMessage = false;
      _notifySafely();
      return;
    }

    await _executeGuidanceRequest(
      request,
      assistantMessageIndex: assistantIndex,
    );
  }

  Future<void> stopGeneratingResponse() async {
    if (!_isSendingMessage || _isStoppingGeneration) {
      return;
    }

    _stopGenerationRequested = true;
    _isStoppingGeneration = true;
    _serviceStatus = 'Menghentikan generasi respons...';
    _notifySafely();

    try {
      await _gemmaService.stopActiveGeneration();
    } catch (error) {
      _serviceStatus = 'Gagal menghentikan generasi respons: $error';
      _stopGenerationRequested = false;
    } finally {
      _isStoppingGeneration = false;
      _notifySafely();
    }
  }

  Future<void> _sendGuidanceRequest({
    required String userMessage,
    required String fallbackInput,
    required String ragQuery,
    bool includePhotoContext = false,
    bool hasPhotoAttachmentWithoutVision = false,
    bool includeAudioContext = false,
    Uint8List? userPhotoBytes,
    String? userPhotoName,
    Uint8List? userAudioBytes,
  }) async {
    final request = AssistantGuidanceRequest(
      userMessage: userMessage,
      fallbackInput: fallbackInput,
      ragQuery: ragQuery,
      includePhotoContext: includePhotoContext,
      hasPhotoAttachmentWithoutVision: hasPhotoAttachmentWithoutVision,
      includeAudioContext: includeAudioContext,
      userPhotoBytes: userPhotoBytes,
      userPhotoName: userPhotoName,
      userAudioBytes: userAudioBytes,
    );

    await _startGuidanceRequest(request);
  }

  Future<void> _startGuidanceRequest(AssistantGuidanceRequest request) async {
    if (_isSendingMessage) {
      return;
    }

    _messages.add(
      AssistantMessage(
        role: 'user',
        text: request.userMessage,
        photoBytes: request.userPhotoBytes,
        photoName: request.userPhotoName,
      ),
    );
    _messages.add(const AssistantMessage(role: 'assistant', text: ''));
    _lastAssistantResponseIndex = _messages.length - 1;
    _lastGuidanceRequest = request;
    _isSendingMessage = true;
    _notifySafely();

    await _executeGuidanceRequest(
      request,
      assistantMessageIndex: _lastAssistantResponseIndex!,
    );
  }

  Future<void> _executeGuidanceRequest(
    AssistantGuidanceRequest request, {
    required int assistantMessageIndex,
  }) async {
    _stopGenerationRequested = false;
    _isStoppingGeneration = false;

    if (!_gemmaService.isReady) {
      await _gemmaService.initializeReadyModel();
    }

    if (!_gemmaService.isReady) {
      _serviceStatus = _gemmaService.statusMessage;
      _replaceAssistantMessageAt(assistantMessageIndex, _serviceStatus);
      _isSendingMessage = false;
      _notifySafely();
      return;
    }

    final buffer = StringBuffer();

    try {
      final ragContext = await _ragService.query(request.ragQuery, limit: 3);
      final prompt = _buildActiveGuidancePrompt(
        userInput: request.fallbackInput,
        ragContext: ragContext,
        includePhotoContext: request.includePhotoContext,
        hasPhotoAttachmentWithoutVision:
            request.hasPhotoAttachmentWithoutVision,
        includeAudioContext: request.includeAudioContext,
      );

      // Selalu gunakan streaming untuk memprioritaskan pengalaman respons yang bertahap buat User
      await for (final token in _streamResponseForRequest(request, prompt)) {
        buffer.write(token);
        _replaceAssistantMessageAt(
          assistantMessageIndex,
          _cleanDisplayText(buffer.toString()),
        );
        _notifySafely();
      }
      if (_stopGenerationRequested) {
        final partialText = _cleanDisplayText(buffer.toString()).trim();
        final stoppedText = partialText.isEmpty
            ? 'Generasi dihentikan sebelum respons selesai.'
            : '$partialText\n\n[Generasi dihentikan]';
        _replaceAssistantMessageAt(assistantMessageIndex, stoppedText);
        _serviceStatus = 'Generasi respons dihentikan.';
        await _gemmaService.resetConversation();
        return;
      }
      if (request.usesImageInference) {
        _visionState = AssistantVisionState.enabled;
      }
      if (request.usesAudioInference &&
          _gemmaService.state == GemmaServiceState.error) {
        final message =
            'Input suara beta belum berhasil di model aktif. Tulis kondisi lewat chat teks dulu agar SIGAP tetap bisa membantu. ${_gemmaService.lastInferenceDebugLabel}';
        _replaceAssistantMessageAt(assistantMessageIndex, message);
        _serviceStatus = message;
        return;
      }
      final guidance = _buildStructuredGuidance(
        rawText: buffer.toString(),
        fallbackInput: request.fallbackInput,
      );
      _urgency = guidance.urgency;
      _replaceAssistantMessageAt(
        assistantMessageIndex,
        guidance.summary,
        guidance: guidance,
      );
      _serviceStatus = _gemmaService.statusMessage;
      await _handleGuidanceSpeech(guidance);
    } catch (error) {
      if (_stopGenerationRequested) {
        final partialText = _cleanDisplayText(buffer.toString()).trim();
        final stoppedText = partialText.isEmpty
            ? 'Generasi dihentikan sebelum respons selesai.'
            : '$partialText\n\n[Generasi dihentikan]';
        _replaceAssistantMessageAt(assistantMessageIndex, stoppedText);
        _serviceStatus = 'Generasi respons dihentikan.';
        await _gemmaService.resetConversation();
        return;
      }
      if (request.usesImageInference) {
        await _fallbackToTextAfterVisionFailure(
          request,
          assistantMessageIndex: assistantMessageIndex,
          error: error,
        );
        return;
      }
      if (request.usesAudioInference) {
        final message =
            'Input suara beta gagal diproses oleh model aktif: $error. Tulis kondisi lewat chat teks dulu agar SIGAP tetap bisa membantu.';
        _replaceAssistantMessageAt(assistantMessageIndex, message);
        _serviceStatus = message;
        return;
      }
      final message = 'Terjadi kesalahan saat memproses pesan: $error';
      _replaceAssistantMessageAt(assistantMessageIndex, message);
      _serviceStatus = message;
    } finally {
      _isSendingMessage = false;
      _isStoppingGeneration = false;
      _stopGenerationRequested = false;
      _notifySafely();
    }
  }

  Future<EmergencyLaunchResult> sendEmergency() async {
    if (_isSendingEmergency) {
      return const EmergencyLaunchResult(
        isSuccess: false,
        message: 'Permintaan darurat sedang diproses.',
      );
    }

    if (!hasEmergencyContact) {
      return const EmergencyLaunchResult(
        isSuccess: false,
        message: 'Kontak darurat belum disimpan.',
        requiresContact: true,
      );
    }

    _isSendingEmergency = true;
    _notifySafely();

    try {
      final position = await _determineCurrentPosition();
      final message = _buildEmergencyMessage(position);
      final phoneDigits = _sanitizeWhatsAppPhone(_emergencyContactPhone!);

      if (phoneDigits.isEmpty) {
        return const EmergencyLaunchResult(
          isSuccess: false,
          message: 'Nomor WhatsApp kontak darurat belum valid.',
          requiresContact: true,
        );
      }

      final whatsappUri = Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: {'phone': phoneDigits, 'text': message},
      );
      final fallbackUri = Uri.https('wa.me', '/$phoneDigits', {
        'text': message,
      });

      final launched =
          await launchUrl(whatsappUri, mode: LaunchMode.externalApplication) ||
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);

      if (!launched) {
        return const EmergencyLaunchResult(
          isSuccess: false,
          message: 'WhatsApp tidak bisa dibuka di perangkat ini.',
        );
      }

      return EmergencyLaunchResult(
        isSuccess: true,
        message:
            'WhatsApp dibuka untuk ${_emergencyContactName!}. Pesan darurat sudah disiapkan.',
      );
    } on LocationServiceDisabledException {
      return const EmergencyLaunchResult(
        isSuccess: false,
        message: 'Layanan lokasi sedang nonaktif. Nyalakan GPS lalu coba lagi.',
      );
    } on PermissionDeniedException catch (error) {
      return EmergencyLaunchResult(isSuccess: false, message: error.message);
    } catch (error) {
      return EmergencyLaunchResult(
        isSuccess: false,
        message: 'Gagal menyiapkan pesan darurat: $error',
      );
    } finally {
      _isSendingEmergency = false;
      _notifySafely();
    }
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

  Stream<String> _streamResponseForRequest(
    AssistantGuidanceRequest request,
    String prompt,
  ) {
    if (request.usesImageInference) {
      return _gemmaService.generateResponseWithImage(
        prompt: prompt,
        imageBytes: request.userPhotoBytes!,
      );
    }

    if (request.usesAudioInference) {
      return _gemmaService.generateResponseWithAudio(
        prompt: prompt,
        audioBytes: request.userAudioBytes!,
      );
    }

    return _gemmaService.generateResponse(prompt);
  }

  void _replaceAssistantMessageAt(
    int index,
    String text, {
    AssistantGuidance? guidance,
  }) {
    if (index < 0 || index >= _messages.length) {
      return;
    }

    _messages[index] = AssistantMessage(
      role: 'assistant',
      text: text,
      guidance: guidance,
    );
  }

  String _buildActiveGuidancePrompt({
    required String userInput,
    required List<String> ragContext,
    bool includePhotoContext = false,
    bool hasPhotoAttachmentWithoutVision = false,
    bool includeAudioContext = false,
  }) {
    final hasContext = ragContext.isNotEmpty;
    final contextBlock = hasContext
        ? ragContext.map((item) => '- $item').join('\n')
        : '- Tidak ada konteks RAG tambahan yang terverifikasi di perangkat saat ini.';
    final modalityBlock = includeAudioContext
        ? '''
Ada satu rekaman suara dari user.
- Dengarkan audio untuk menangkap laporan kondisi darurat.
- Jika audio tidak jelas, terlalu pendek, atau bahasa tidak terbaca, jangan menebak detail medis.
- Bila informasi penting belum jelas, minta user mengulang atau menulis lewat chat: usia korban, gejala utama, kesadaran, napas, perdarahan, dan durasi kejadian.
- Tetap berikan langkah aman yang konservatif berdasarkan informasi yang terdengar jelas saja.
'''
        : includePhotoContext
        ? '''
Ada satu foto luka atau kondisi P3K dari kamera user.
- Fokuskan observasi visual pada triase luka atau kondisi pertolongan pertama, bukan deskripsi umum foto.
- Gunakan bahasa konservatif seperti "dari foto tampak kemungkinan..." atau "bagian ini terlihat..." bila visual tidak sepenuhnya jelas.
- Jangan mengarang luka, warna, perdarahan, lepuh, kedalaman luka, atau benda asing bila tidak terlihat jelas.
- Jika foto kurang jelas, akui keterbatasannya dengan jujur lalu minta konfirmasi detail penting.
- Wajib minta klarifikasi bila lokasi luka, perdarahan, luas luka, lepuh, benda menancap, atau kesadaran korban belum jelas.
'''
        : hasPhotoAttachmentWithoutVision
        ? '''
User melampirkan foto luka atau kondisi P3K, tetapi analisis visual native sedang dimatikan atau gagal demi stabilitas runtime perangkat.
- Jangan mengklaim bisa melihat atau menganalisis foto.
- Gunakan hanya deskripsi teks user.
- Jika informasi visual masih kurang, minta user menjelaskan lokasi luka, perdarahan, ukuran, lepuh, benda menancap, dan kesadaran korban.
'''
        : 'Tidak ada foto terlampir pada permintaan ini.';

    return '''
Anda adalah SIGAP, asisten pertolongan pertama offline untuk warga awam di situasi darurat.

Tugas Anda:
1. Fokus pada langkah pertolongan pertama yang aman, konservatif, dan praktis.
2. Jangan memberi diagnosis pasti.
3. Utamakan tindakan yang bisa dilakukan sekarang sambil menyarankan bantuan medis bila perlu.
4. Untuk luka bakar, pendarahan, tersedak, kejang, pingsan, atau nyeri dada, berikan langkah yang singkat dan jelas.
5. Jangan gunakan markdown tebal, bullet aneh, atau paragraf panjang.
6. Untuk foto atau gejala yang ambigu, katakan dengan jujur bahwa AI bisa salah dan pemeriksaan tenaga medis tetap penting.

Balas WAJIB dengan format persis seperti ini:
URGENCY: GREEN atau YELLOW atau RED
SUMMARY: satu sampai dua kalimat ringkas tentang kondisi dan prioritas tindakan. Jika ada foto, tekankan bahwa penilaian visual ini bisa keliru.
WARNING: satu kalimat peringatan paling penting. Jika ada ketidakpastian, sebut jelas bahwa AI bisa salah dan user perlu periksa ke dokter atau fasilitas kesehatan bila luka tampak berat, kotor, dalam, atau memburuk.
STEPS:
1. Judul langkah | detail tindakan
2. Judul langkah | detail tindakan
3. Judul langkah | detail tindakan
QUESTIONS:
- pertanyaan lanjutan pertama
- pertanyaan lanjutan kedua

Buat 3 sampai 5 langkah. Jika kondisi tampak berat, pilih YELLOW atau RED.
Jika ini berpotensi gawat darurat, arahkan untuk mencari bantuan medis segera.
Gunakan konteks RAG lokal bila relevan, dan jangan mengarang fakta di luar konteks itu untuk klaim P3K spesifik.
Jika tool tersedia, gunakan tool untuk sinkronkan urgensi, tandai situasi darurat, dan koreksi mitos yang jelas sebelum memberi respons akhir.
Input mode user saat ini: $_inputMode
Konteks RAG lokal SIGAP:
$contextBlock
Konteks multimodal:
$modalityBlock
Laporan user: $userInput
''';
  }

  AssistantGuidance _buildStructuredGuidance({
    required String rawText,
    required String fallbackInput,
  }) {
    final cleanedRaw = _cleanDisplayText(rawText);
    final urgency = _parseUrgency(cleanedRaw, fallbackInput);
    final summary =
        _extractSingleLine(cleanedRaw, 'SUMMARY') ??
        _buildFallbackSummary(cleanedRaw, fallbackInput);
    final warning =
        _extractSingleLine(cleanedRaw, 'WARNING') ??
        _buildFallbackWarning(urgency, fallbackInput);
    final steps = _extractSteps(cleanedRaw, fallbackInput, urgency);
    final followUpQuestions = _extractQuestions(cleanedRaw, fallbackInput);

    return AssistantGuidance(
      urgency: urgency,
      summary: summary,
      warning: warning,
      steps: steps,
      followUpQuestions: followUpQuestions,
      rawText: cleanedRaw,
    );
  }

  UrgencyLevel _parseUrgency(String rawText, String fallbackInput) {
    final upperText = rawText.toUpperCase();
    final upperInput = fallbackInput.toUpperCase();
    if (upperText.contains('URGENCY: RED') ||
        upperText.contains('RED') ||
        upperInput.contains('PINGSAN') ||
        upperInput.contains('KEJANG') ||
        upperInput.contains('TERSEDAK') ||
        upperInput.contains('SESAK') ||
        upperInput.contains('TIDAK SADAR')) {
      return UrgencyLevel.red;
    }
    if (upperText.contains('URGENCY: YELLOW') ||
        upperInput.contains('LUKA BAKAR') ||
        upperInput.contains('KNALPOT') ||
        upperInput.contains('PENDARAHAN') ||
        upperInput.contains('LUKA')) {
      return UrgencyLevel.yellow;
    }
    return UrgencyLevel.green;
  }

  String? _extractSingleLine(String rawText, String label) {
    final prefix = '$label:';
    for (final line in rawText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toUpperCase().startsWith(prefix)) {
        final value = trimmed.substring(prefix.length).trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  List<AssistantGuidanceStep> _extractSteps(
    String rawText,
    String fallbackInput,
    UrgencyLevel urgency,
  ) {
    final lines = rawText.split('\n');
    final steps = <AssistantGuidanceStep>[];
    var inSteps = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.toUpperCase() == 'STEPS:') {
        inSteps = true;
        continue;
      }
      if (trimmed.toUpperCase() == 'QUESTIONS:') {
        break;
      }
      if (!inSteps || trimmed.isEmpty) {
        continue;
      }

      final match = RegExp(r'^\d+\.\s*(.+)$').firstMatch(trimmed);
      if (match == null) {
        continue;
      }

      final content = match.group(1)!.trim();
      final parts = content.split('|');
      final title = parts.first.trim();
      final details = parts.length > 1
          ? parts.sublist(1).join('|').trim()
          : content.trim();
      steps.add(
        AssistantGuidanceStep(
          title: title.isEmpty ? 'Langkah ${steps.length + 1}' : title,
          details: details,
        ),
      );
    }

    if (steps.isNotEmpty) {
      return steps;
    }

    if (_looksLikeBurnCase(fallbackInput)) {
      return const [
        AssistantGuidanceStep(
          title: 'Jauhkan dari sumber panas',
          details:
              'Pastikan kulit tidak lagi menyentuh knalpot atau benda panas lain.',
        ),
        AssistantGuidanceStep(
          title: 'Dinginkan luka',
          details:
              'Aliri dengan air mengalir suhu normal selama sekitar 20 menit. Jangan pakai es, pasta gigi, atau mentega.',
        ),
        AssistantGuidanceStep(
          title: 'Lepas benda yang ketat',
          details:
              'Lepas cincin, gelang, atau pakaian ketat di sekitar area sebelum bengkak bertambah, jika tidak menempel pada luka.',
        ),
        AssistantGuidanceStep(
          title: 'Tutup longgar',
          details:
              'Setelah didinginkan, tutup dengan kain bersih atau kasa non lengket. Jangan pecahkan lepuh.',
        ),
      ];
    }

    return [
      AssistantGuidanceStep(
        title: 'Amankan kondisi',
        details: urgency == UrgencyLevel.red
            ? 'Segera minta bantuan orang sekitar dan hubungi layanan darurat bila kondisi memburuk atau korban tidak responsif.'
            : 'Pastikan area aman dan jauhkan korban dari penyebab cedera.',
      ),
      const AssistantGuidanceStep(
        title: 'Nilai gejala utama',
        details:
            'Perhatikan nyeri hebat, perdarahan, kesulitan bernapas, pingsan, atau penurunan kesadaran.',
      ),
      const AssistantGuidanceStep(
        title: 'Cari bantuan medis bila perlu',
        details:
            'Jika gejala berat, meluas, atau tidak membaik, segera menuju fasilitas kesehatan terdekat.',
      ),
    ];
  }

  List<String> _extractQuestions(String rawText, String fallbackInput) {
    final lines = rawText.split('\n');
    final questions = <String>[];
    var inQuestions = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.toUpperCase() == 'QUESTIONS:') {
        inQuestions = true;
        continue;
      }
      if (!inQuestions || trimmed.isEmpty) {
        continue;
      }
      if (trimmed.startsWith('-')) {
        final question = trimmed.substring(1).trim();
        if (question.isNotEmpty) {
          questions.add(question);
        }
      }
    }

    if (questions.isNotEmpty) {
      return questions.take(2).toList();
    }

    if (_looksLikeBurnCase(fallbackInput)) {
      return const [
        'Apakah ada lepuh, kulit mengelupas, atau area luka cukup luas?',
        'Apakah luka mengenai wajah, tangan, kelamin, atau sendi besar?',
      ];
    }

    return const [
      'Apakah ada gejala yang semakin berat saat ini?',
      'Apakah korban tetap sadar dan bisa merespons dengan jelas?',
    ];
  }

  String _buildFallbackSummary(String rawText, String fallbackInput) {
    if (_looksLikeBurnCase(fallbackInput)) {
      return 'Ini tampak seperti luka bakar kontak. Prioritas awalnya adalah mendinginkan area luka dan memantau tanda luka yang lebih berat.';
    }

    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isNotEmpty) {
      return lines.first;
    }
    return 'SIGAP sedang membantu menyusun langkah pertolongan pertama yang aman untuk kondisi ini.';
  }

  String _buildFallbackWarning(UrgencyLevel urgency, String fallbackInput) {
    if (_looksLikeBurnCase(fallbackInput)) {
      return 'Jangan oles pasta gigi, mentega, kopi, atau es langsung pada luka bakar.';
    }
    if (urgency == UrgencyLevel.red) {
      return 'Ini berpotensi gawat darurat. Segera cari bantuan medis atau hubungi layanan darurat.';
    }
    if (urgency == UrgencyLevel.yellow) {
      return 'Jika gejala memburuk, area luka meluas, atau korban tampak lemah, segera ke fasilitas kesehatan.';
    }
    return 'Pantau perubahan gejala dan cari bantuan medis jika kondisi tidak membaik.';
  }

  bool _looksLikeBurnCase(String input) {
    final normalized = input.toLowerCase();
    return normalized.contains('knalpot') ||
        normalized.contains('luka bakar') ||
        normalized.contains('terbakar') ||
        normalized.contains('kena panas');
  }

  String _cleanDisplayText(String text) {
    return text
        .replaceAll('**', '')
        .replaceAll('* ', '')
        .replaceAllMapped(RegExp(r'\n{3,}'), (_) => '\n\n')
        .trim();
  }

  Future<void> _initializeTts() async {
    try {
      await _ttsService.initialize();
      _ttsEnabled = _ttsService.isEnabled;
      _ttsSpeechRate = _ttsService.speechRate;
    } catch (error) {
      _serviceStatus = 'TTS belum siap dipakai: $error';
    }
  }

  Future<void> _loadEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    _emergencyContactName = prefs.getString(_emergencyContactNameKey)?.trim();
    _emergencyContactPhone = prefs.getString(_emergencyContactPhoneKey)?.trim();
  }

  Future<void> _loadVisionBetaPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _isVisionBetaEnabled = prefs.getBool(_visionBetaEnabledKey) ?? false;
    _visionState = _isVisionBetaEnabled
        ? AssistantVisionState.enabled
        : AssistantVisionState.disabled;
  }

  Future<void> _fallbackToTextAfterVisionFailure(
    AssistantGuidanceRequest request, {
    required int assistantMessageIndex,
    required Object error,
  }) async {
    _visionState = AssistantVisionState.visionFailedFallback;
    final fallbackRequest = AssistantGuidanceRequest(
      userMessage: request.userMessage,
      fallbackInput: request.fallbackInput,
      ragQuery: request.ragQuery,
      hasPhotoAttachmentWithoutVision: true,
      userPhotoBytes: request.userPhotoBytes,
      userPhotoName: request.userPhotoName,
    );
    _lastGuidanceRequest = fallbackRequest;
    _serviceStatus =
        'Analisis Foto Beta gagal: $error. SIGAP kembali memakai deskripsi teks untuk menjaga stabilitas.';
    _replaceAssistantMessageAt(
      assistantMessageIndex,
      'Analisis Foto Beta gagal di perangkat ini. SIGAP kembali memakai deskripsi teks untuk menyusun panduan yang lebih aman.',
    );
    _notifySafely();

    final ragContext = await _ragService.query(
      fallbackRequest.ragQuery,
      limit: 3,
    );
    final fallbackPrompt = _buildActiveGuidancePrompt(
      userInput: fallbackRequest.fallbackInput,
      ragContext: ragContext,
      includePhotoContext: false,
      hasPhotoAttachmentWithoutVision: true,
    );
    final buffer = StringBuffer();
    await for (final token in _streamResponseForRequest(
      fallbackRequest,
      fallbackPrompt,
    )) {
      buffer.write(token);
      _replaceAssistantMessageAt(
        assistantMessageIndex,
        _cleanDisplayText(buffer.toString()),
      );
      _notifySafely();
    }
    final guidance = _buildStructuredGuidance(
      rawText: buffer.toString(),
      fallbackInput: fallbackRequest.fallbackInput,
    );
    _urgency = guidance.urgency;
    _replaceAssistantMessageAt(
      assistantMessageIndex,
      guidance.summary,
      guidance: guidance,
    );
    _serviceStatus =
        'Analisis Foto Beta gagal lalu fallback ke teks. ${_gemmaService.lastInferenceDebugLabel}';
    await _handleGuidanceSpeech(guidance);
  }

  Future<Position> _determineCurrentPosition() async {
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isServiceEnabled) {
      throw LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const PermissionDeniedException(
          'Izin lokasi ditolak. SIGAP butuh GPS untuk mengirim titik darurat.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException(
        'Izin lokasi ditolak permanen. Buka pengaturan aplikasi untuk mengaktifkan GPS SIGAP.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  String _buildEmergencyMessage(Position position) {
    AssistantGuidance? latestGuidance;
    for (final message in _messages.reversed) {
      if (message.guidance != null) {
        latestGuidance = message.guidance;
        break;
      }
    }
    final latestUserMessage = _messages.reversed
        .firstWhere(
          (message) => message.isUser && message.text.trim().isNotEmpty,
          orElse: () => const AssistantMessage(
            role: 'user',
            text: 'Kondisi darurat belum dijelaskan detail.',
          ),
        )
        .text;

    final guidanceSummary =
        latestGuidance?.summary ??
        'Butuh bantuan segera. Mohon cek kondisi korban secepatnya.';
    final urgencyLabel = latestGuidance?.urgency.label ?? 'Panggil Bantuan';
    final mapsLink =
        'https://maps.google.com/?q=${position.latitude},${position.longitude}';

    return '''
SIGAP butuh bantuan darurat.

Kontak tujuan: ${_emergencyContactName ?? 'Kontak darurat'}
Level urgensi: $urgencyLabel
Ringkasan kondisi: $guidanceSummary
Laporan singkat user: $latestUserMessage
Lokasi GPS: ${position.latitude}, ${position.longitude}
Buka peta: $mapsLink
'''
        .trim();
  }

  String _sanitizeWhatsAppPhone(String rawPhone) {
    final digitsOnly = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.startsWith('0')) {
      return '62${digitsOnly.substring(1)}';
    }
    return digitsOnly;
  }

  Future<void> _handleGuidanceSpeech(AssistantGuidance guidance) async {
    if (!_ttsEnabled && guidance.urgency != UrgencyLevel.red) {
      return;
    }

    if (!_ttsEnabled && guidance.urgency == UrgencyLevel.red) {
      _ttsEnabled = await _ttsService.toggle();
      _notifySafely();
    }

    await _speakGuidance(guidance);
  }

  Future<void> _speakLatestGuidanceIfAvailable() async {
    for (final message in _messages.reversed) {
      final guidance = message.guidance;
      if (guidance != null) {
        await _speakGuidance(guidance);
        return;
      }
    }
  }

  Future<void> _speakGuidance(AssistantGuidance guidance) async {
    try {
      await _ttsService.speak(_buildSpeechText(guidance));
    } catch (error) {
      _serviceStatus = 'Panduan suara gagal diputar: $error';
      _notifySafely();
    }
  }

  String _buildSpeechText(AssistantGuidance guidance) {
    final buffer = StringBuffer()
      ..writeln(guidance.summary)
      ..writeln()
      ..writeln('Perhatian: ${guidance.warning}');

    for (var index = 0; index < guidance.steps.length; index++) {
      final step = guidance.steps[index];
      buffer.writeln();
      buffer.writeln('Langkah ${index + 1}. ${step.title}. ${step.details}');
    }

    return buffer.toString().trim();
  }

  String? _formatRecordingDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) {
      return null;
    }

    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _connectivitySubscription?.cancel();
    _voiceRecordingTimer?.cancel();
    _gemmaService.removeListener(_handleServiceUpdate);
    unawaited(_gemmaService.stopActiveGeneration());
    unawaited(_ttsService.stop());
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }
}

class LocationServiceDisabledException implements Exception {}

class PermissionDeniedException implements Exception {
  const PermissionDeniedException(this.message);

  final String message;
}

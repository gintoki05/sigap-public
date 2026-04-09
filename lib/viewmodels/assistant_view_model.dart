import 'dart:async';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../services/gemma_service.dart';
import '../services/rag_service.dart';
import '../services/tts_service.dart';

class AssistantGuidanceStep {
  const AssistantGuidanceStep({
    required this.title,
    required this.details,
  });

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
  });

  final String role;
  final String text;
  final AssistantGuidance? guidance;

  bool get isUser => role == 'user';
  bool get hasStructuredGuidance => guidance != null;

  AssistantMessage copyWith({
    String? role,
    String? text,
    AssistantGuidance? guidance,
  }) {
    return AssistantMessage(
      role: role ?? this.role,
      text: text ?? this.text,
      guidance: guidance ?? this.guidance,
    );
  }
}

class AssistantPhotoAttachment {
  const AssistantPhotoAttachment({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
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
  static const bool _enableNativeVisionInference = false;

  AssistantViewModel({
    required String inputMode,
    GemmaService? gemmaService,
    Connectivity? connectivity,
    RagService? ragService,
    TtsService? ttsService,
  })  : _inputMode = inputMode,
        _gemmaService = gemmaService ?? GemmaService(),
        _ragService = ragService ?? RagService(),
        _ttsService = ttsService ?? TtsService(),
        _connectivity = connectivity ?? Connectivity() {
    _serviceStatus = _gemmaService.statusMessage;
  }

  final String _inputMode;
  final GemmaService _gemmaService;
  final RagService _ragService;
  final TtsService _ttsService;
  final Connectivity _connectivity;

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

  bool get isModelReady => _gemmaService.isReady;
  bool get isDownloading => _gemmaService.isDownloading;
  bool get isDeleting => _gemmaService.isDeleting;
  int get downloadProgress => _gemmaService.downloadProgress;
  Duration? get downloadEta => _gemmaService.downloadEta;
  bool get isImportingLocalModel => _isImportingLocalModel;
  bool get isSendingEmergency => _isSendingEmergency;
  bool get hasEmergencyContact =>
      (_emergencyContactName?.trim().isNotEmpty ?? false) &&
      (_emergencyContactPhone?.trim().isNotEmpty ?? false);

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
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectivityState);
    await _refreshConnectivityState();
    await _loadEmergencyContact();
    await _ragService.initialize();
    await _initializeTts();
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
      responseStreamBuilder: (prompt) => _gemmaService.generateResponse(prompt),
    );
  }

  void startVoice() {
    _serviceStatus =
        'Input suara belum tersedia pada model aktif SIGAP. Dukungan audio di flutter_gemma masih perlu divalidasi untuk artefak model yang dipakai sekarang.';
    _notifySafely();
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
      return AssistantPhotoAttachment(
        name: pickedFile.name,
        bytes: imageBytes,
      );
    } catch (error) {
      _serviceStatus = 'Gagal mengambil foto kondisi: $error';
      _notifySafely();
      return null;
    }
  }

  Future<void> sendPhotoMessage({
    required Uint8List imageBytes,
    String text = '',
  }) async {
    final trimmedDraft = text.trim();

    if (!_enableNativeVisionInference) {
      _serviceStatus =
          'Foto diterima sebagai lampiran, tetapi analisis visual otomatis sedang dimatikan di perangkat ini untuk mencegah crash native.';

      if (trimmedDraft.isEmpty) {
        _messages.add(
          const AssistantMessage(
            role: 'user',
            text: 'Saya melampirkan foto kondisi.',
          ),
        );
        _messages.add(
          const AssistantMessage(
            role: 'assistant',
            text:
                'Analisis foto otomatis sedang dimatikan di perangkat ini untuk menjaga stabilitas. Tambahkan deskripsi singkat tentang apa yang terlihat pada foto, lalu kirim lagi agar SIGAP bisa memberi panduan yang lebih tepat.',
          ),
        );
        _notifySafely();
        return;
      }

      await _sendGuidanceRequest(
        userMessage: 'Saya mengirim foto kondisi. Catatan: $trimmedDraft',
        fallbackInput: trimmedDraft,
        ragQuery: trimmedDraft,
        responseStreamBuilder: (prompt) => _gemmaService.generateResponse(prompt),
        hasPhotoAttachmentWithoutVision: true,
      );
      return;
    }

    final userMessage = trimmedDraft.isEmpty
        ? 'Saya mengirim foto kondisi untuk dianalisis.'
        : 'Saya mengirim foto kondisi. Catatan: $trimmedDraft';
    final fallbackInput = trimmedDraft.isEmpty
        ? 'Foto kondisi darurat dari kamera pengguna.'
        : trimmedDraft;

    await _sendGuidanceRequest(
      userMessage: userMessage,
      fallbackInput: fallbackInput,
      ragQuery: trimmedDraft.isEmpty
          ? 'analisis foto kondisi darurat'
          : trimmedDraft,
      responseStreamBuilder: (prompt) => _gemmaService.generateResponseWithImage(
        prompt: prompt,
        imageBytes: imageBytes,
      ),
      includePhotoContext: true,
    );
  }

  Future<void> _sendGuidanceRequest({
    required String userMessage,
    required String fallbackInput,
    required String ragQuery,
    required Stream<String> Function(String prompt) responseStreamBuilder,
    bool includePhotoContext = false,
    bool hasPhotoAttachmentWithoutVision = false,
  }) async {
    if (_isSendingMessage) {
      return;
    }

    _messages.add(AssistantMessage(role: 'user', text: userMessage));
    _messages.add(const AssistantMessage(role: 'assistant', text: ''));
    _isSendingMessage = true;
    _notifySafely();

    if (!_gemmaService.isReady) {
      await _gemmaService.initializeReadyModel();
    }

    if (!_gemmaService.isReady) {
      _serviceStatus = _gemmaService.statusMessage;
      _replaceLastAssistantMessage(_serviceStatus);
      _isSendingMessage = false;
      _notifySafely();
      return;
    }

    final buffer = StringBuffer();

    try {
      final ragContext = await _ragService.query(ragQuery, limit: 3);
      final prompt = _buildActiveGuidancePrompt(
        userInput: fallbackInput,
        ragContext: ragContext,
        includePhotoContext: includePhotoContext,
        hasPhotoAttachmentWithoutVision: hasPhotoAttachmentWithoutVision,
      );
      await for (final token in responseStreamBuilder(prompt)) {
        buffer.write(token);
        _replaceLastAssistantMessage(_cleanDisplayText(buffer.toString()));
        _notifySafely();
      }
      final guidance = _buildStructuredGuidance(
        rawText: buffer.toString(),
        fallbackInput: fallbackInput,
      );
      _urgency = guidance.urgency;
      _replaceLastAssistantMessage(
        guidance.summary,
        guidance: guidance,
      );
      _serviceStatus = _gemmaService.statusMessage;
      await _handleGuidanceSpeech(guidance);
    } catch (error) {
      final message = 'Terjadi kesalahan saat memproses pesan: $error';
      _replaceLastAssistantMessage(message);
      _serviceStatus = message;
    } finally {
      _isSendingMessage = false;
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
        queryParameters: {
          'phone': phoneDigits,
          'text': message,
        },
      );
      final fallbackUri = Uri.https(
        'wa.me',
        '/$phoneDigits',
        {'text': message},
      );

      final launched = await launchUrl(
            whatsappUri,
            mode: LaunchMode.externalApplication,
          ) ||
          await launchUrl(
            fallbackUri,
            mode: LaunchMode.externalApplication,
          );

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
      return EmergencyLaunchResult(
        isSuccess: false,
        message: error.message,
      );
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

  void _replaceLastAssistantMessage(
    String text, {
    AssistantGuidance? guidance,
  }) {
    if (_messages.isEmpty) {
      return;
    }

    _messages[_messages.length - 1] = AssistantMessage(
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
  }) {
    final hasContext = ragContext.isNotEmpty;
    final contextBlock = hasContext
        ? ragContext.map((item) => '- $item').join('\n')
        : '- Tidak ada konteks RAG tambahan yang terverifikasi di perangkat saat ini.';
    final modalityBlock = includePhotoContext
        ? '''
Ada satu foto kondisi dari kamera user.
- Gunakan foto hanya untuk membantu mengamati kondisi yang tampak.
- Jika detail visual tidak jelas, katakan keterbatasannya dengan jujur.
- Jangan mengarang luka, warna, perdarahan, atau benda asing bila tidak terlihat jelas.
'''
        : hasPhotoAttachmentWithoutVision
        ? '''
User melampirkan foto kondisi, tetapi analisis visual native sedang dimatikan demi stabilitas runtime perangkat.
- Jangan mengklaim bisa melihat atau menganalisis foto.
- Gunakan hanya deskripsi teks user.
- Jika informasi visual masih kurang, minta user menjelaskan apa yang terlihat pada foto.
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

Balas WAJIB dengan format persis seperti ini:
URGENCY: GREEN atau YELLOW atau RED
SUMMARY: satu sampai dua kalimat ringkas tentang kondisi dan prioritas tindakan
WARNING: satu kalimat peringatan paling penting. Jika tidak ada, tulis "Tidak ada warning khusus."
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
    final summary = _extractSingleLine(cleanedRaw, 'SUMMARY') ??
        _buildFallbackSummary(cleanedRaw, fallbackInput);
    final warning = _extractSingleLine(cleanedRaw, 'WARNING') ??
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
        details:
            urgency == UrgencyLevel.red
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
        .replaceAllMapped(
          RegExp(r'\n{3,}'),
          (_) => '\n\n',
        )
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

    final guidanceSummary = latestGuidance?.summary ??
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
'''.trim();
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
      buffer.writeln(
        'Langkah ${index + 1}. ${step.title}. ${step.details}',
      );
    }

    return buffer.toString().trim();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _connectivitySubscription?.cancel();
    _gemmaService.removeListener(_handleServiceUpdate);
    unawaited(_ttsService.stop());
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

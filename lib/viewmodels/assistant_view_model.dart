import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../services/gemma_service.dart';
import '../services/rag_service.dart';

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

class AssistantViewModel extends ChangeNotifier {
  AssistantViewModel({
    required String inputMode,
    GemmaService? gemmaService,
    Connectivity? connectivity,
    RagService? ragService,
  })  : _inputMode = inputMode,
        _gemmaService = gemmaService ?? GemmaService(),
        _ragService = ragService ?? RagService(),
        _connectivity = connectivity ?? Connectivity() {
    _serviceStatus = _gemmaService.statusMessage;
  }

  final String _inputMode;
  final GemmaService _gemmaService;
  final RagService _ragService;
  final Connectivity _connectivity;

  final List<AssistantMessage> _messages = [];
  UrgencyLevel _urgency = UrgencyLevel.green;

  bool _ttsEnabled = false;
  bool? _isOnWifi;
  String _serviceStatus = 'Model Gemma belum diinisialisasi.';
  bool _isDisposed = false;
  bool _isImportingLocalModel = false;
  bool _isSendingMessage = false;
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
  bool get isImportingLocalModel => _isImportingLocalModel;

  bool get isBusy {
    return _isImportingLocalModel ||
        _isSendingMessage ||
        _gemmaService.state == GemmaServiceState.initializing ||
        _gemmaService.state == GemmaServiceState.checking ||
        _gemmaService.state == GemmaServiceState.deleting;
  }

  Future<void> initialize() async {
    _gemmaService.addListener(_handleServiceUpdate);
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectivityState);
    await _refreshConnectivityState();
    await _ragService.initialize();
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
    if (trimmedText.isEmpty || _isSendingMessage) {
      return;
    }

    _messages.add(AssistantMessage(role: 'user', text: trimmedText));
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
      final ragContext = await _ragService.query(trimmedText, limit: 3);
      final prompt = _buildActiveGuidancePrompt(
        userInput: trimmedText,
        ragContext: ragContext,
      );
      await for (final token in _gemmaService.generateResponse(prompt)) {
        buffer.write(token);
        _replaceLastAssistantMessage(
          _cleanDisplayText(buffer.toString()),
        );
        _notifySafely();
      }
      final guidance = _buildStructuredGuidance(
        rawText: buffer.toString(),
        fallbackInput: trimmedText,
      );
      _urgency = guidance.urgency;
      _replaceLastAssistantMessage(
        guidance.summary,
        guidance: guidance,
      );
      _serviceStatus = _gemmaService.statusMessage;
    } catch (error) {
      final message = 'Terjadi kesalahan saat memproses pesan: $error';
      _replaceLastAssistantMessage(message);
      _serviceStatus = message;
    } finally {
      _isSendingMessage = false;
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
  }) {
    final hasContext = ragContext.isNotEmpty;
    final contextBlock = hasContext
        ? ragContext.map((item) => '- $item').join('\n')
        : '- Tidak ada konteks RAG tambahan yang terverifikasi di perangkat saat ini.';

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

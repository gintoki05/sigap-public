import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/gemma_service.dart';

class AssistantScreen extends StatefulWidget {
  final String initialInputMode;
  final String? initialQuery;

  const AssistantScreen({
    super.key,
    this.initialInputMode = 'chat',
    this.initialQuery,
  });

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final GemmaService _gemmaService = GemmaService();
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final UrgencyLevel _urgency = UrgencyLevel.green;
  bool _ttsEnabled = false;
  String _serviceStatus = 'Model Gemma belum diinisialisasi.';

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _controller.text = widget.initialQuery!.trim();
    }
    _serviceStatus = _gemmaService.statusMessage;
    _initializeReadyModel();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Asisten P3K',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _ttsEnabled = !_ttsEnabled),
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off),
            tooltip: 'Suarakan instruksi',
          ),
        ],
      ),
      body: Column(
        children: [
          _UrgencyBanner(level: _urgency),
          _ModelStatusBanner(
            isReady: _gemmaService.isReady,
            status: _serviceStatus,
            progress: _gemmaService.downloadProgress,
            isDownloading: _gemmaService.isDownloading,
          ),
          Expanded(
            child: _gemmaService.isReady
                ? (_messages.isEmpty
                    ? _EmptyState(
                        inputMode: widget.initialInputMode,
                        serviceStatus: _serviceStatus,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) =>
                            _MessageBubble(message: _messages[i]),
                      ))
                : _ModelSetupPanel(
                    service: _gemmaService,
                    status: _serviceStatus,
                    onDownload: _downloadModel,
                    onRetry: _initializeReadyModel,
                  ),
          ),
          if (_gemmaService.isReady && _isBusy())
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(width: 16),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'SIGAP sedang berpikir...',
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
          if (_gemmaService.isReady)
            _BottomInputBar(
              controller: _controller,
              onSend: _sendMessage,
              onVoice: _startVoice,
              onPhoto: _pickPhoto,
              onEmergency: _sendEmergency,
            ),
        ],
      ),
    );
  }

  bool _isBusy() {
    return _gemmaService.state == GemmaServiceState.initializing ||
        _gemmaService.state == GemmaServiceState.checking;
  }

  Future<void> _initializeReadyModel() async {
    setState(() {});
    await _gemmaService.initializeReadyModel();
    if (!mounted) {
      return;
    }
    setState(() {
      _serviceStatus = _gemmaService.statusMessage;
    });
  }

  Future<void> _downloadModel() async {
    setState(() {});
    await _gemmaService.downloadAndInstallModel();
    if (!mounted) {
      return;
    }
    setState(() {
      _serviceStatus = _gemmaService.statusMessage;
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _controller.clear();
      _messages.add({'role': 'assistant', 'text': ''});
    });

    if (!_gemmaService.isReady) {
      await _gemmaService.initializeReadyModel();
    }

    if (!_gemmaService.isReady) {
      if (!mounted) {
        return;
      }
      setState(() {
        _serviceStatus = _gemmaService.statusMessage;
        _messages.last['text'] = _serviceStatus;
      });
      return;
    }

    final buffer = StringBuffer();

    try {
      await for (final token in _gemmaService.generateResponse(text)) {
        buffer.write(token);
        if (!mounted) {
          return;
        }
        setState(() {
          _messages.last['text'] = buffer.toString();
        });
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _serviceStatus = _gemmaService.statusMessage;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.last['text'] = 'Terjadi kesalahan saat memproses pesan: $error';
        _serviceStatus = _messages.last['text'] as String;
      });
    }
  }

  void _startVoice() {
    // TODO: Implement voice input via flutter_gemma audio
  }

  void _pickPhoto() {
    // TODO: Implement image_picker + flutter_gemma vision
  }

  void _sendEmergency() {
    // TODO: Implement geolocator + url_launcher WhatsApp
  }
}

class _ModelStatusBanner extends StatelessWidget {
  final bool isReady;
  final String status;
  final int progress;
  final bool isDownloading;

  const _ModelStatusBanner({
    required this.isReady,
    required this.status,
    required this.progress,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isReady
        ? AppColors.urgencyGreen.withValues(alpha: 0.12)
        : AppColors.urgencyYellow.withValues(alpha: 0.18);
    final foregroundColor = isReady ? AppColors.urgencyGreen : AppColors.navy;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isReady ? Icons.check_circle_outline : Icons.info_outline,
                color: foregroundColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress > 0 ? progress / 100 : null,
              minHeight: 6,
              color: AppColors.navy,
              backgroundColor: Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelSetupPanel extends StatelessWidget {
  final GemmaService service;
  final String status;
  final Future<void> Function() onDownload;
  final Future<void> Function() onRetry;

  const _ModelSetupPanel({
    required this.service,
    required this.status,
    required this.onDownload,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy = service.state == GemmaServiceState.downloading ||
        service.state == GemmaServiceState.initializing ||
        service.state == GemmaServiceState.checking;
    final showDownloadButton =
        service.needsDownload && !service.hasConfiguredLocalPath;
    final showRetryButton =
        !showDownloadButton && service.canRetry && !service.isDownloading;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.download_for_offline_outlined,
                        color: AppColors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Setup Gemma 4 Sekali Saja',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'SIGAP perlu mengunduh model Gemma 4 E4B-IT ke perangkat Anda. Setelah selesai, asisten AI bisa dipakai secara lokal dan offline tanpa mengunduh ulang.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textDark,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _SetupFact(
                  icon: Icons.sd_storage_outlined,
                  label: 'Ukuran model',
                  value: service.estimatedModelSizeLabel,
                ),
                _SetupFact(
                  icon: Icons.signal_wifi_statusbar_4_bar,
                  label: 'Koneksi awal',
                  value: service.hasConfiguredLocalPath
                      ? 'Mode developer: file lokal'
                      : 'Perlu internet untuk download pertama',
                ),
                const _SetupFact(
                  icon: Icons.offline_bolt_outlined,
                  label: 'Setelah setup',
                  value: 'Berjalan offline di perangkat',
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                ),
                if (service.isDownloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: service.downloadProgress > 0
                        ? service.downloadProgress / 100
                        : null,
                    minHeight: 8,
                    color: AppColors.red,
                    backgroundColor: AppColors.red.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${service.downloadProgress}% selesai',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (showDownloadButton)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isBusy ? null : onDownload,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Model Sekarang'),
                    ),
                  ),
                if (showRetryButton)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(service.hasConfiguredLocalPath
                          ? 'Coba Muat Model Lokal Lagi'
                          : 'Periksa Lagi Status Model'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupFact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SetupFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgencyBanner extends StatelessWidget {
  final UrgencyLevel level;

  const _UrgencyBanner({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: level.color.withValues(alpha: 0.15),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: level.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            level.label,
            style: TextStyle(color: level.color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String inputMode;
  final String serviceStatus;

  const _EmptyState({
    required this.inputMode,
    required this.serviceStatus,
  });

  @override
  Widget build(BuildContext context) {
    final prompt = switch (inputMode) {
      'voice' => 'Mode suara dipilih.\nModel akan dipakai setelah Gemma siap.',
      'photo' => 'Mode foto dipilih.\nFitur vision belum diaktifkan pada tahap PRI-51.',
      _ => 'Ceritakan kondisi darurat\natau tekan BICARA',
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 64,
            color: AppColors.navy.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            prompt,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textGrey, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              serviceStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border:
              isUser ? null : Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
        ),
        child: Text(
          message['text'] as String,
          style: TextStyle(color: isUser ? Colors.white : AppColors.textDark),
        ),
      ),
    );
  }
}

class _BottomInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onVoice;
  final VoidCallback onPhoto;
  final VoidCallback onEmergency;

  const _BottomInputBar({
    required this.controller,
    required this.onSend,
    required this.onVoice,
    required this.onPhoto,
    required this.onEmergency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onEmergency,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.location_on),
              label: const Text(
                'KIRIM LOKASI SAYA',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: onVoice,
                icon: const Icon(Icons.mic, color: AppColors.navy),
              ),
              IconButton(
                onPressed: onPhoto,
                icon: const Icon(Icons.camera_alt, color: AppColors.navy),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Ketik kondisi darurat...',
                    hintStyle: const TextStyle(color: AppColors.textGrey),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              IconButton(
                onPressed: onSend,
                icon: const Icon(Icons.send, color: AppColors.navy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

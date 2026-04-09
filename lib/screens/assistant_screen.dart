import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../services/gemma_service.dart';
import '../viewmodels/assistant_view_model.dart';

class AssistantScreen extends StatelessWidget {
  final String initialInputMode;
  final String? initialQuery;

  const AssistantScreen({
    super.key,
    this.initialInputMode = 'chat',
    this.initialQuery,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          AssistantViewModel(inputMode: initialInputMode)..initialize(),
      child: _AssistantScreenBody(initialQuery: initialQuery),
    );
  }
}

class _AssistantScreenBody extends StatefulWidget {
  const _AssistantScreenBody({this.initialQuery});

  final String? initialQuery;

  @override
  State<_AssistantScreenBody> createState() => _AssistantScreenBodyState();
}

class _AssistantScreenBodyState extends State<_AssistantScreenBody> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialQuery?.trim() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AssistantViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Asisten P3K',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (viewModel.isModelReady)
            IconButton(
              onPressed: viewModel.isBusy
                  ? null
                  : () => _deleteModel(context, viewModel),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus model',
            ),
          IconButton(
            onPressed: viewModel.toggleTts,
            icon: Icon(
              viewModel.ttsEnabled ? Icons.volume_up : Icons.volume_off,
            ),
            tooltip: 'Suarakan instruksi',
          ),
        ],
      ),
      body: Column(
        children: [
          _UrgencyBanner(level: viewModel.urgency),
          _ModelStatusBanner(
            isReady: viewModel.isModelReady,
            status: viewModel.serviceStatus,
            progress: viewModel.downloadProgress,
            isDownloading: viewModel.isDownloading,
            isDeleting: viewModel.isDeleting,
            eta: viewModel.downloadEta,
          ),
          Expanded(
            child: viewModel.isModelReady
                ? (viewModel.messages.isEmpty
                      ? _EmptyState(
                          inputMode: viewModel.inputMode,
                          serviceStatus: viewModel.serviceStatus,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: viewModel.messages.length,
                          itemBuilder: (context, index) {
                            final message = viewModel.messages[index];
                            if (message.hasStructuredGuidance) {
                              return _GuidanceCard(message: message);
                            }
                            return _MessageBubble(message: message);
                          },
                        ))
                : _ModelSetupPanel(
                    service: viewModel.gemmaService,
                    status: viewModel.serviceStatus,
                    isBusy: viewModel.isBusy,
                    installedVariants: viewModel.installedVariants,
                    isOnWifi: viewModel.isOnWifi,
                    isDeleting: viewModel.isDeleting,
                    onSelectVariant: viewModel.selectVariant,
                    onDownload: () => _downloadModel(context, viewModel),
                    onImportLocalFile: viewModel.importLocalModel,
                    onCancelDownload: () => _cancelDownload(context, viewModel),
                    onDelete: () => _deleteModel(context, viewModel),
                    onRetry: viewModel.initializeReadyModel,
                  ),
          ),
          if (viewModel.isModelReady)
            _BottomInputBar(
              controller: _controller,
              onSend: () => _sendMessage(viewModel),
              onVoice: viewModel.startVoice,
              onPhoto: viewModel.pickPhoto,
              onEmergency: viewModel.sendEmergency,
            ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(AssistantViewModel viewModel) async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    _controller.clear();
    await viewModel.sendMessage(text);
  }

  Future<void> _downloadModel(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    if (viewModel.isOnWifi == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Anda tidak sedang memakai Wi-Fi. Download ${viewModel.gemmaService.selectedModelLabel} ${viewModel.gemmaService.estimatedModelSizeLabel} dan bisa menghabiskan kuota data seluler.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    await viewModel.downloadModel();
  }

  Future<void> _deleteModel(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    final isInstalled = await viewModel.isSelectedModelInstalled();
    if (!context.mounted || !isInstalled) {
      return;
    }

    final modelLabel = viewModel.gemmaService.selectedModelLabel;
    final modelSize = viewModel.gemmaService.estimatedModelSizeLabel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus model?'),
        content: Text(
          '$modelLabel akan dihapus dari perangkat dan ruang penyimpanan sekitar $modelSize akan dibebaskan. Anda bisa mengunduhnya lagi kapan saja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await viewModel.deleteSelectedModel();
  }

  Future<void> _cancelDownload(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    if (!viewModel.isDownloading) {
      return;
    }

    final modelLabel = viewModel.gemmaService.selectedModelLabel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan download?'),
        content: Text(
          'Download $modelLabel akan dihentikan sekarang. Anda bisa memulainya lagi kapan saja nanti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Lanjut download'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await viewModel.cancelDownload();
  }
}

class _ModelStatusBanner extends StatelessWidget {
  final bool isReady;
  final String status;
  final int progress;
  final bool isDownloading;
  final bool isDeleting;
  final Duration? eta;

  const _ModelStatusBanner({
    required this.isReady,
    required this.status,
    required this.progress,
    required this.isDownloading,
    required this.isDeleting,
    required this.eta,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isReady
        ? AppColors.urgencyGreen.withValues(alpha: 0.12)
        : AppColors.urgencyYellow.withValues(alpha: 0.18);
    final foregroundColor = isReady ? AppColors.urgencyGreen : AppColors.navy;
    final statusLabel = isReady
        ? 'Model siap'
        : isDeleting
        ? 'Menghapus model'
        : isDownloading
        ? 'Sedang download'
        : 'Perlu setup';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
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
            if (eta != null) ...[
              const SizedBox(height: 6),
              Text(
                eta == Duration.zero
                    ? 'Menyelesaikan proses akhir...'
                    : 'Sisa sekitar ${_formatEta(eta!)}',
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'Menghitung sisa waktu...',
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatEta(Duration eta) {
    if (eta.inHours >= 1) {
      final hours = eta.inHours;
      final minutes = eta.inMinutes.remainder(60);
      return minutes > 0 ? '$hours jam $minutes menit' : '$hours jam';
    }
    if (eta.inMinutes >= 1) {
      final minutes = eta.inMinutes;
      final seconds = eta.inSeconds.remainder(60);
      return seconds > 0 ? '$minutes menit $seconds detik' : '$minutes menit';
    }
    return '${eta.inSeconds.clamp(1, 59)} detik';
  }
}

class _ModelSetupPanel extends StatelessWidget {
  final GemmaService service;
  final String status;
  final bool isBusy;
  final Map<SigapModelVariant, bool> installedVariants;
  final bool? isOnWifi;
  final bool isDeleting;
  final Future<void> Function(SigapModelVariant variant) onSelectVariant;
  final Future<void> Function() onDownload;
  final Future<void> Function() onImportLocalFile;
  final Future<void> Function() onCancelDownload;
  final Future<void> Function() onDelete;
  final Future<void> Function() onRetry;

  const _ModelSetupPanel({
    required this.service,
    required this.status,
    required this.isBusy,
    required this.installedVariants,
    required this.isOnWifi,
    required this.isDeleting,
    required this.onSelectVariant,
    required this.onDownload,
    required this.onImportLocalFile,
    required this.onCancelDownload,
    required this.onDelete,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isServiceBusy =
        service.state == GemmaServiceState.downloading ||
        service.state == GemmaServiceState.deleting ||
        service.state == GemmaServiceState.initializing ||
        service.state == GemmaServiceState.checking;
    final selectedModelInstalled =
        installedVariants[service.selectedVariant] ?? false;
    final showDownloadButton =
        service.needsDownload && !service.hasConfiguredLocalPath;
    final showRetryButton =
        !showDownloadButton && service.canRetry && !service.isDownloading;
    final showDeleteButton =
        !service.hasConfiguredLocalPath &&
        !showDownloadButton &&
        !isDeleting &&
        !service.isDownloading;

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
                    const Expanded(
                      child: Text(
                        'Pilih Model Offline',
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
                  'Pilih model yang ingin disiapkan di perangkat, lalu unduh sekali agar asisten AI bisa dipakai secara lokal tanpa internet.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textDark,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.navy.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Text(
                    'Ringkasnya: pilih E2B bila ingin mulai lebih cepat. Pilih E4B bila device Anda kuat dan Anda ingin kualitas respons yang lebih tinggi.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textDark,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final variant in GemmaService.supportedVariants) ...[
                  _VariantOptionCard(
                    variant: variant,
                    isSelected: service.selectedVariant == variant,
                    isInstalled: installedVariants[variant] ?? false,
                    onTap: isBusy ? null : () => onSelectVariant(variant),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                _SetupFact(
                  icon: Icons.memory_outlined,
                  label: 'Model terpilih',
                  value: service.selectedModelLabel,
                ),
                _SetupFact(
                  icon: Icons.sd_storage_outlined,
                  label: 'Ukuran',
                  value: service.estimatedModelSizeLabel,
                ),
                _SetupFact(
                  icon: Icons.signal_wifi_statusbar_4_bar,
                  label: 'Koneksi awal',
                  value: service.hasConfiguredLocalPath
                      ? 'Mode developer: file lokal'
                      : isOnWifi == null
                      ? 'Memeriksa jenis koneksi...'
                      : isOnWifi!
                      ? 'Wi-Fi terdeteksi, aman untuk download pertama'
                      : 'Bukan Wi-Fi, perhatikan kuota data',
                ),
                const _SetupFact(
                  icon: Icons.offline_bolt_outlined,
                  label: 'Setelah setup',
                  value: 'Berjalan offline di perangkat',
                ),
                if (!service.hasConfiguredLocalPath && isOnWifi == false) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.urgencyYellow.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.urgencyYellow.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          color: AppColors.navy,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Download model Gemma 4 cukup besar. Disarankan memakai Wi-Fi agar proses awal lebih stabil dan tidak menguras kuota data.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textDark,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  if (service.downloadEta != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      service.downloadEta == Duration.zero
                          ? 'Menyelesaikan proses akhir...'
                          : 'Sisa sekitar ${_formatEta(service.downloadEta!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Menghitung sisa waktu...',
                      style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : onImportLocalFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      service.isUsingImportedLocalModel
                          ? 'Ganti File ${service.selectedModelLabel}'
                          : 'Impor File ${service.selectedModelLabel}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isBusy
                        ? null
                        : showDownloadButton
                        ? onDownload
                        : onRetry,
                    icon: Icon(
                      showDownloadButton
                          ? Icons.download
                          : selectedModelInstalled
                          ? Icons.play_arrow
                          : Icons.refresh,
                    ),
                    label: Text(
                      showDownloadButton
                          ? 'Download ${service.selectedModelLabel}'
                          : selectedModelInstalled
                          ? 'Gunakan ${service.selectedModelLabel}'
                          : 'Periksa ${service.selectedModelLabel}',
                    ),
                  ),
                ),
                if (showRetryButton)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isBusy ? null : onRetry,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          service.hasConfiguredLocalPath
                              ? 'Coba Muat Model Lokal Lagi'
                              : 'Periksa Lagi Status Model',
                        ),
                      ),
                    ),
                  ),
                if (showDeleteButton) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : onDelete,
                      icon: const Icon(Icons.delete_outline),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: const BorderSide(color: AppColors.red),
                      ),
                      label: Text('Hapus ${service.selectedModelLabel}'),
                    ),
                  ),
                ],
                if (service.isDownloading) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCancelDownload,
                      icon: const Icon(Icons.close),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: const BorderSide(color: AppColors.red),
                      ),
                      label: const Text('Batalkan Download'),
                    ),
                  ),
                ],
                if (!service.isDownloading && isBusy && !isServiceBusy) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Menyiapkan impor model. Mohon tunggu sebentar...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatEta(Duration eta) {
    if (eta.inHours >= 1) {
      final hours = eta.inHours;
      final minutes = eta.inMinutes.remainder(60);
      return minutes > 0 ? '$hours jam $minutes menit' : '$hours jam';
    }
    if (eta.inMinutes >= 1) {
      final minutes = eta.inMinutes;
      final seconds = eta.inSeconds.remainder(60);
      return seconds > 0 ? '$minutes menit $seconds detik' : '$minutes menit';
    }
    return '${eta.inSeconds.clamp(1, 59)} detik';
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
              style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantOptionCard extends StatelessWidget {
  final SigapModelVariant variant;
  final bool isSelected;
  final bool isInstalled;
  final VoidCallback? onTap;

  const _VariantOptionCard({
    required this.variant,
    required this.isSelected,
    required this.isInstalled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final benefitColor = variant.isRecommended
        ? AppColors.urgencyGreen
        : AppColors.red;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.red.withValues(alpha: 0.08)
                : AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.red
                  : AppColors.navy.withValues(alpha: 0.12),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      variant.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  if (variant.isRecommended)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.urgencyGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Rekomendasi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.urgencyGreen,
                        ),
                      ),
                    ),
                  if (isInstalled) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Sudah terpasang',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                variant.setupDescription,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textDark,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniPill(
                    icon: Icons.bolt_outlined,
                    label: variant.bestForLabel,
                    backgroundColor: benefitColor.withValues(alpha: 0.10),
                    foregroundColor: benefitColor,
                  ),
                  _MiniPill(
                    icon: Icons.offline_bolt_outlined,
                    label: 'Offline penuh',
                    backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                    foregroundColor: AppColors.navy,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sd_storage_outlined,
                        size: 16,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        variant.estimatedSizeLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_outlined,
                        size: 16,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        variant.bestForLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _MiniPill({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: foregroundColor,
              fontWeight: FontWeight.w700,
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
    final helperText = switch (level) {
      UrgencyLevel.green =>
        'Fokus pada langkah aman mandiri sambil terus pantau gejala.',
      UrgencyLevel.yellow =>
        'Butuh penanganan cepat dan evaluasi medis bila gejala tidak membaik.',
      UrgencyLevel.red =>
        'Prioritaskan bantuan darurat dan jangan tunda mencari pertolongan medis.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: level.color.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: level.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                level.label,
                style: TextStyle(
                  color: level.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            helperText,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String inputMode;
  final String serviceStatus;

  const _EmptyState({required this.inputMode, required this.serviceStatus});

  @override
  Widget build(BuildContext context) {
    final prompt = switch (inputMode) {
      'voice' => 'Mode suara dipilih.\nModel akan dipakai setelah Gemma siap.',
      'photo' =>
        'Mode foto dipilih.\nFitur vision belum diaktifkan pada tahap PRI-51.',
      _ => 'Ceritakan kondisi darurat\natau tekan BICARA',
    };

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
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
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 16,
                  ),
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
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AssistantMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isAssistantPlaceholder = !message.isUser && message.text.trim().isEmpty;

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: message.isUser
              ? null
              : Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
        ),
        child: isAssistantPlaceholder
            ? const Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SIGAP sedang menyusun balasan...',
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                  ),
                ],
              )
            : Text(
                message.text,
                style: TextStyle(
                  color: message.isUser ? Colors.white : AppColors.textDark,
                ),
              ),
      ),
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({required this.message});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final guidance = message.guidance!;
    final urgencyColor = guidance.urgency.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: urgencyColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: urgencyColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              guidance.urgency.label,
              style: TextStyle(
                color: urgencyColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            guidance.summary,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _WarningBox(
            color: urgencyColor,
            warning: guidance.warning,
          ),
          const SizedBox(height: 14),
          const Text(
            'Langkah yang disarankan',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < guidance.steps.length; i++) ...[
            _StepCard(
              index: i + 1,
              step: guidance.steps[i],
            ),
            if (i != guidance.steps.length - 1) const SizedBox(height: 10),
          ],
          if (guidance.followUpQuestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Pertanyaan lanjutan',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            for (final question in guidance.followUpQuestions) ...[
              _FollowUpQuestion(question: question),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({
    required this.color,
    required this.warning,
  });

  final Color color;
  final String warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              warning,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.step,
  });

  final int index;
  final AssistantGuidanceStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.navy,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.details,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGrey,
                    height: 1.45,
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

class _FollowUpQuestion extends StatelessWidget {
  const _FollowUpQuestion({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.help_outline_rounded,
            color: AppColors.navy,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              question,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDark,
                height: 1.4,
              ),
            ),
          ),
        ],
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

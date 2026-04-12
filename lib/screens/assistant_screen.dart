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
  static const List<String> _photoDescriptionPrompts = [
    'Lokasi luka di...',
    'Jenis luka: lecet/sayat/bakar',
    'Perdarahan: tidak ada/ringan/aktif',
    'Ukuran atau luas kira-kira...',
    'Korban sadar dan bisa merespons',
  ];

  late final TextEditingController _controller;
  AssistantPhotoAttachment? _pendingPhoto;
  bool _hasAutoStartedVoice = false;
  bool _hasAutoOpenedPhoto = false;

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
    final selectedModelInstalled =
        viewModel.installedVariants[viewModel.gemmaService.selectedVariant] ??
        false;
    final shouldKeepAssistantScrollable =
        selectedModelInstalled &&
        (viewModel.gemmaService.state == GemmaServiceState.initializing ||
            viewModel.gemmaService.state == GemmaServiceState.checking);
    final showAssistantShell =
        viewModel.isModelReady || shouldKeepAssistantScrollable;
    _maybeAutoStartVoice(viewModel);
    _maybeAutoOpenPhoto(viewModel);

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
                  : () => _showStatusDetailsSheet(context, viewModel),
              icon: const Icon(Icons.storage_rounded),
              tooltip: 'Kelola model',
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
          _CompactStatusStrip(
            level: viewModel.urgency,
            isReady: viewModel.isModelReady,
            status: viewModel.serviceStatus,
            isDownloading: viewModel.isDownloading,
            isDeleting: viewModel.isDeleting,
            eta: viewModel.downloadEta,
            onTap: () => _showStatusDetailsSheet(context, viewModel),
          ),
          Expanded(
            child: showAssistantShell
                ? (viewModel.messages.isEmpty
                      ? _EmptyState(
                          inputMode: viewModel.inputMode,
                          hasPendingPhoto: _pendingPhoto != null,
                          serviceStatus: viewModel.serviceStatus,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: viewModel.messages.length,
                          itemBuilder: (context, index) {
                            final message = viewModel.messages[index];
                            final canRegenerateMessage =
                                !message.isUser &&
                                index == viewModel.messages.length - 1 &&
                                viewModel.canRegenerateLatestResponse;
                            if (message.hasStructuredGuidance) {
                              return _GuidanceCard(
                                message: message,
                                speechRate: viewModel.ttsSpeechRate,
                                onReplay: () =>
                                    viewModel.replayGuidance(message.guidance!),
                                onRegenerate: canRegenerateMessage
                                    ? viewModel.regenerateLatestResponse
                                    : null,
                                onAdjustSpeed: () =>
                                    _showTtsSpeedSheet(context, viewModel),
                              );
                            }
                            return _MessageBubble(
                              message: message,
                              onRegenerate: canRegenerateMessage
                                  ? viewModel.regenerateLatestResponse
                                  : null,
                            );
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
            SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).viewInsets.bottom > 0
                      ? 220
                      : 320,
                ),
                child: _BottomInputBar(
                  controller: _controller,
                  onSend: () => _sendMessage(viewModel),
                  onVoice: viewModel.startVoice,
                  onPhoto: () => _pickPhoto(viewModel),
                  onEmergency: () => _sendEmergency(context, viewModel),
                  isBusy: viewModel.isSendingEmergency,
                  emergencyContactName: viewModel.emergencyContactName,
                  emergencyContactPhone: viewModel.emergencyContactPhone,
                  onEditEmergencyContact: () =>
                      _showEmergencyContactDialog(context, viewModel),
                  pendingPhoto: _pendingPhoto,
                  onRemovePhoto: _clearPendingPhoto,
                  onApplyPhotoPrompt: _applyPhotoPrompt,
                  isRecordingVoice: viewModel.isRecordingVoice,
                  voiceRecordingDuration: viewModel.voiceRecordingDuration,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _maybeAutoStartVoice(AssistantViewModel viewModel) {
    final shouldAutoStart =
        !_hasAutoStartedVoice &&
        widget.initialQuery == null &&
        viewModel.inputMode == 'voice' &&
        viewModel.isModelReady &&
        !viewModel.isBusy &&
        !viewModel.isRecordingVoice &&
        viewModel.messages.isEmpty;

    if (!shouldAutoStart) {
      return;
    }

    _hasAutoStartedVoice = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      viewModel.startVoice();
    });
  }

  void _maybeAutoOpenPhoto(AssistantViewModel viewModel) {
    final shouldAutoOpenPhoto =
        !_hasAutoOpenedPhoto &&
        widget.initialQuery == null &&
        viewModel.inputMode == 'photo' &&
        viewModel.isModelReady &&
        !viewModel.isBusy &&
        !viewModel.isRecordingVoice &&
        _pendingPhoto == null &&
        viewModel.messages.isEmpty;

    if (!shouldAutoOpenPhoto) {
      return;
    }

    _hasAutoOpenedPhoto = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _pickPhoto(viewModel);
    });
  }

  Future<void> _sendMessage(AssistantViewModel viewModel) async {
    final text = _controller.text.trim();
    final pendingPhoto = _pendingPhoto;
    if (text.isEmpty && pendingPhoto == null) {
      return;
    }

    _controller.clear();
    _clearPendingPhoto();
    if (pendingPhoto != null) {
      await viewModel.sendPhotoMessage(
        imageBytes: pendingPhoto.bytes,
        photoName: pendingPhoto.name,
        text: text,
      );
      return;
    }

    await viewModel.sendMessage(text);
  }

  Future<void> _pickPhoto(AssistantViewModel viewModel) async {
    final photo = await viewModel.capturePhoto();
    if (!mounted || photo == null) {
      return;
    }

    if (!viewModel.isVisionBetaEnabled) {
      await viewModel.setVisionBetaEnabled(true);
    }

    setState(() {
      _pendingPhoto = photo;
    });
  }

  void _clearPendingPhoto() {
    if (!mounted) {
      return;
    }

    setState(() {
      _pendingPhoto = null;
    });
  }

  void _applyPhotoPrompt(String prompt) {
    final currentText = _controller.text.trim();
    final nextText = currentText.isEmpty ? prompt : '$currentText; $prompt';

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
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

  void _dismissActiveInput(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
  }

  Future<void> _deleteModel(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    _dismissActiveInput(context);

    final isInstalled = await viewModel.isSelectedModelInstalled();
    if (!context.mounted || !isInstalled) {
      return;
    }

    final modelLabel = viewModel.gemmaService.selectedModelLabel;
    final modelSize = viewModel.gemmaService.estimatedModelSizeLabel;
    var hasAcknowledgedRedownload = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Hapus model?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$modelLabel akan dihapus dari perangkat dan ruang penyimpanan sekitar $modelSize akan dibebaskan.',
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.urgencyYellow.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.urgencyYellow.withValues(alpha: 0.32),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.navy,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Model offline berukuran besar. Jika dihapus, Anda mungkin perlu download ulang yang cukup lama dan bisa menghabiskan banyak kuota.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textDark,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: hasAcknowledgedRedownload,
                onChanged: (value) {
                  setDialogState(() {
                    hasAcknowledgedRedownload = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Saya paham model harus diunduh ulang jika nanti dibutuhkan.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: hasAcknowledgedRedownload
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Hapus'),
            ),
          ],
        ),
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
    _dismissActiveInput(context);

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

  Future<void> _showTtsSpeedSheet(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    _dismissActiveInput(context);

    double draftRate = viewModel.ttsSpeechRate;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kecepatan Panduan Suara',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Atur kecepatan yang paling nyaman untuk diikuti saat menolong korban.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textGrey.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Lambat',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            draftRate.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        const Text(
                          'Cepat',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: draftRate,
                      min: 0.3,
                      max: 0.8,
                      divisions: 10,
                      label: draftRate.toStringAsFixed(2),
                      onChanged: (value) async {
                        setModalState(() => draftRate = value);
                        await viewModel.setTtsSpeechRate(value);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showStatusDetailsSheet(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    _dismissActiveInput(context);

    final urgencyHelperText = switch (viewModel.urgency) {
      UrgencyLevel.green =>
        'Fokus pada langkah aman mandiri sambil terus memantau perubahan gejala.',
      UrgencyLevel.yellow =>
        'Butuh penanganan cepat dan evaluasi medis bila gejala tidak membaik.',
      UrgencyLevel.red =>
        'Prioritaskan bantuan darurat dan jangan menunda mencari pertolongan medis.',
    };

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status Assistant',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 16),
                _StatusDetailTile(
                  icon: Icons.flag_outlined,
                  title: 'Level urgensi',
                  value: viewModel.urgency.label,
                  helperText: urgencyHelperText,
                  accentColor: viewModel.urgency.color,
                ),
                const SizedBox(height: 12),
                _StatusDetailTile(
                  icon: viewModel.isModelReady
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  title: 'Status model',
                  value: viewModel.serviceStatus,
                  helperText: viewModel.downloadEta == null
                      ? null
                      : viewModel.downloadEta == Duration.zero
                      ? 'Menyelesaikan proses akhir.'
                      : 'Sisa sekitar ${_formatEta(viewModel.downloadEta!)}.',
                  accentColor: viewModel.isModelReady
                      ? AppColors.urgencyGreen
                      : AppColors.navy,
                ),
                if (viewModel.isModelReady && !viewModel.isBusy) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _deleteModel(context, viewModel);
                      },
                      icon: const Icon(Icons.delete_outline),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: const BorderSide(color: AppColors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      label: const Text('Hapus Model Dari Perangkat'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

  Future<void> _sendEmergency(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    _dismissActiveInput(context);

    if (!viewModel.hasEmergencyContact) {
      final didSaveContact = await _showEmergencyContactDialog(
        context,
        viewModel,
      );
      if (didSaveContact != true || !context.mounted) {
        return;
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Menyiapkan lokasi dan pesan darurat...'),
        duration: Duration(seconds: 2),
      ),
    );

    final result = await viewModel.sendEmergency();
    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess
            ? AppColors.urgencyGreen
            : AppColors.red,
      ),
    );

    if (result.requiresContact) {
      await _showEmergencyContactDialog(context, viewModel);
    }
  }

  Future<bool?> _showEmergencyContactDialog(
    BuildContext context,
    AssistantViewModel viewModel,
  ) async {
    _dismissActiveInput(context);

    var name = viewModel.emergencyContactName ?? '';
    var phone = viewModel.emergencyContactPhone ?? '';
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Simpan Kontak Darurat'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(
                      labelText: 'Nama kontak',
                      hintText: 'Misalnya Ibu, Kakak, atau Tetangga',
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (value) => name = value,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor WhatsApp',
                      hintText: '08xxxxxxxxxx',
                    ),
                    onChanged: (value) => phone = value,
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Nanti saja'),
                ),
                FilledButton(
                  onPressed: () async {
                    final trimmedName = name.trim();
                    final trimmedPhone = phone.trim();
                    if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
                      setDialogState(() {
                        errorText =
                            'Nama dan nomor WhatsApp harus diisi supaya SIGAP bisa menyiapkan pesan darurat.';
                      });
                      return;
                    }

                    await viewModel.saveEmergencyContact(
                      name: trimmedName,
                      phone: trimmedPhone,
                    );

                    if (context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
    return saved;
  }
}

class _CompactStatusStrip extends StatelessWidget {
  const _CompactStatusStrip({
    required this.level,
    required this.isReady,
    required this.status,
    required this.isDownloading,
    required this.isDeleting,
    required this.eta,
    required this.onTap,
  });

  final UrgencyLevel level;
  final bool isReady;
  final String status;
  final bool isDownloading;
  final bool isDeleting;
  final Duration? eta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final modelLabel = isReady
        ? 'Model siap'
        : isDeleting
        ? 'Menghapus model'
        : isDownloading
        ? 'Download model'
        : 'Perlu setup';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.navy.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              _InlineStatusPill(
                label: level.label,
                backgroundColor: level.color.withValues(alpha: 0.12),
                foregroundColor: level.color,
                icon: Icons.circle,
                iconSize: 9,
              ),
              const SizedBox(width: 8),
              _InlineStatusPill(
                label: modelLabel,
                backgroundColor:
                    (isReady ? AppColors.urgencyGreen : AppColors.navy)
                        .withValues(alpha: 0.08),
                foregroundColor: isReady
                    ? AppColors.urgencyGreen
                    : AppColors.navy,
                icon: isReady ? Icons.check_circle_outline : Icons.memory,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  eta != null && isDownloading
                      ? 'Sisa ${eta == Duration.zero ? 'sebentar lagi' : _compactEta(eta!)}'
                      : status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textGrey.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compactEta(Duration eta) {
    if (eta.inMinutes >= 1) {
      return '${eta.inMinutes} menit';
    }
    return '${eta.inSeconds.clamp(1, 59)} detik';
  }
}

class _InlineStatusPill extends StatelessWidget {
  const _InlineStatusPill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    this.iconSize = 14,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final double iconSize;

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
          Icon(icon, size: iconSize, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDetailTile extends StatelessWidget {
  const _StatusDetailTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.accentColor,
    this.helperText,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? helperText;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (helperText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    helperText!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
                  'Pilih model, lalu lakukan setup sekali agar asisten bisa dipakai offline di perangkat.',
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
                    'E2B lebih ringan untuk mulai cepat. E4B lebih berat, tapi respons biasanya lebih baik.',
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

class _EmptyState extends StatelessWidget {
  final String inputMode;
  final bool hasPendingPhoto;
  final String serviceStatus;

  const _EmptyState({
    required this.inputMode,
    required this.hasPendingPhoto,
    required this.serviceStatus,
  });

  @override
  Widget build(BuildContext context) {
    final prompt = switch (inputMode) {
      'voice' => 'Mode suara dipilih.\nModel akan dipakai setelah Gemma siap.',
      'photo' when hasPendingPhoto =>
        'Foto sudah dilampirkan.\nTambahkan deskripsi singkat lalu kirim.',
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
  final Future<void> Function()? onRegenerate;

  const _MessageBubble({required this.message, this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    final isAssistantPlaceholder =
        !message.isUser && message.text.trim().isEmpty;
    final bubbleTextColor = message.isUser ? Colors.white : AppColors.textDark;

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.hasPhoto) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        message.photoBytes!,
                        width: double.infinity,
                        height: 164,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if ((message.photoName?.trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 8),
                      Text(
                        message.photoName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bubbleTextColor.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (message.text.trim().isNotEmpty)
                      const SizedBox(height: 10),
                  ],
                  if (message.text.trim().isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(color: bubbleTextColor),
                    ),
                  if (onRegenerate != null && !message.isUser) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onRegenerate,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Regenerate'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({
    required this.message,
    required this.speechRate,
    required this.onReplay,
    required this.onRegenerate,
    required this.onAdjustSpeed,
  });

  final AssistantMessage message;
  final double speechRate;
  final Future<void> Function() onReplay;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function() onAdjustSpeed;

  @override
  Widget build(BuildContext context) {
    final guidance = message.guidance!;
    final urgencyColor = guidance.urgency.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: urgencyColor.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
          const SizedBox(height: 10),
          Text(
            guidance.summary,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _GuidanceActionButton(
                  onPressed: onReplay,
                  icon: Icons.volume_up_outlined,
                  label: 'Putar Lagi',
                ),
                const SizedBox(width: 8),
                _GuidanceActionButton(
                  onPressed: onAdjustSpeed,
                  icon: Icons.speed_outlined,
                  label: speechRate.toStringAsFixed(2),
                ),
                if (onRegenerate != null) ...[
                  const SizedBox(width: 8),
                  _GuidanceActionButton(
                    onPressed: onRegenerate,
                    icon: Icons.refresh_rounded,
                    label: 'Regenerate',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          _WarningBox(color: urgencyColor, warning: guidance.warning),
          const SizedBox(height: 12),
          const Text(
            'Langkah yang disarankan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < guidance.steps.length; i++) ...[
            _StepCard(index: i + 1, step: guidance.steps[i]),
            if (i != guidance.steps.length - 1) const SizedBox(height: 8),
          ],
          if (guidance.followUpQuestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                minTileHeight: 40,
                dense: true,
                title: const Text(
                  'Pertanyaan lanjutan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                children: [
                  const SizedBox(height: 4),
                  for (final question in guidance.followUpQuestions) ...[
                    _FollowUpQuestion(question: question),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuidanceActionButton extends StatelessWidget {
  const _GuidanceActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final Future<void> Function()? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed == null ? null : () => onPressed!.call(),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: BorderSide(color: AppColors.navy.withValues(alpha: 0.14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.color, required this.warning});

  final Color color;
  final String warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
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
                fontSize: 12,
                height: 1.4,
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
  const _StepCard({required this.index, required this.step});

  final int index;
  final AssistantGuidanceStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  step.details,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                    height: 1.4,
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
  final Future<void> Function() onSend;
  final Future<void> Function() onVoice;
  final Future<void> Function() onPhoto;
  final Future<void> Function() onEmergency;
  final bool isBusy;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final Future<bool?> Function() onEditEmergencyContact;
  final AssistantPhotoAttachment? pendingPhoto;
  final VoidCallback onRemovePhoto;
  final ValueChanged<String> onApplyPhotoPrompt;
  final bool isRecordingVoice;
  final Duration voiceRecordingDuration;

  const _BottomInputBar({
    required this.controller,
    required this.onSend,
    required this.onVoice,
    required this.onPhoto,
    required this.onEmergency,
    required this.isBusy,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.onEditEmergencyContact,
    required this.pendingPhoto,
    required this.onRemovePhoto,
    required this.onApplyPhotoPrompt,
    required this.isRecordingVoice,
    required this.voiceRecordingDuration,
  });

  @override
  Widget build(BuildContext context) {
    final hasEmergencyContact =
        (emergencyContactName?.trim().isNotEmpty ?? false) &&
        (emergencyContactPhone?.trim().isNotEmpty ?? false);

    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pendingPhoto != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.navy.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        pendingPhoto!.bytes,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Foto siap dikirim',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pendingPhoto!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onRemovePhoto,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textGrey,
                      ),
                      tooltip: 'Hapus foto',
                    ),
                  ],
                ),
              ),
            if (isRecordingVoice)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, size: 18, color: AppColors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Merekam suara ${_formatDuration(voiceRecordingDuration)}. Tekan mikrofon lagi untuk kirim.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (pendingPhoto != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.navy.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.medical_information_outlined,
                          size: 18,
                          color: AppColors.navy,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SIGAP akan mencoba membaca foto luka ini. Tetap tambahkan deskripsi singkat agar hasil lebih aman jika visual kurang jelas atau perlu fallback.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _AssistantScreenBodyState
                            ._photoDescriptionPrompts
                            .map(
                              (prompt) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text(prompt),
                                  labelStyle: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor: Colors.white,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  side: BorderSide(
                                    color: AppColors.navy.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                  onPressed: () => onApplyPhotoPrompt(prompt),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () async => onVoice(),
                  icon: Icon(
                    isRecordingVoice ? Icons.stop_circle : Icons.mic,
                    color: isRecordingVoice ? AppColors.red : AppColors.navy,
                  ),
                  tooltip: isRecordingVoice
                      ? 'Stop dan kirim rekaman'
                      : 'Rekam suara',
                ),
                IconButton(
                  onPressed: () async => onPhoto(),
                  icon: const Icon(Icons.camera_alt, color: AppColors.navy),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: pendingPhoto != null
                          ? 'Contoh: Luka sayat di telapak tangan, berdarah ringan, sekitar 2 cm. Tolong cek apakah tampak perlu tindakan cepat.'
                          : 'Ketik kondisi...',
                      hintStyle: const TextStyle(color: AppColors.textGrey),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () async => onSend(),
                  icon: const Icon(Icons.send, color: AppColors.navy),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: isBusy ? null : () async => onEmergency(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.red,
                          ),
                        )
                      : const Icon(Icons.emergency_share_outlined, size: 16),
                  label: Text(isBusy ? 'Menyiapkan...' : 'Darurat'),
                ),
                const Spacer(),
                Flexible(
                  child: TextButton.icon(
                    onPressed: onEditEmergencyContact,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.contact_phone_outlined, size: 16),
                    label: Text(
                      hasEmergencyContact
                          ? emergencyContactName!
                          : 'Kontak darurat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

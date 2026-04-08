import 'package:flutter/material.dart';
import '../core/constants.dart';

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
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final UrgencyLevel _urgency = UrgencyLevel.green;
  bool _ttsEnabled = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten P3K', style: TextStyle(fontWeight: FontWeight.bold)),
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
          // Urgency indicator
          _UrgencyBanner(level: _urgency),

          // Chat messages
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _MessageBubble(message: _messages[i]),
                  ),
          ),

          // Loading indicator
          if (_isLoading)
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
                  Text('SIGAP sedang berpikir...', style: TextStyle(color: AppColors.textGrey)),
                ],
              ),
            ),

          // Tombol darurat + input
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

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _controller.clear();
      _isLoading = true;
    });
    // TODO: Kirim ke GemmaService
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'text': 'Model Gemma 4 belum terhubung. Selesaikan PRI-51 terlebih dahulu.',
          });
          _isLoading = false;
        });
      }
    });
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
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.health_and_safety_outlined, size: 64, color: AppColors.navy.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text(
            'Ceritakan kondisi darurat\natau tekan BICARA',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textGrey, fontSize: 16),
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isUser ? null : Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
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
          // Tombol darurat
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onEmergency,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.location_on),
              label: const Text(
                'KIRIM LOKASI SAYA',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Input row
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

import 'package:flutter/material.dart';
import '../core/constants.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _articles = [
    {
      'title': 'P3K Dasar',
      'subtitle': 'Panduan pertolongan pertama untuk warga awam',
      'icon': '🩺',
      'saved': false,
    },
    {
      'title': 'Pencegahan Stunting',
      'subtitle': 'Nutrisi dan tumbuh kembang balita',
      'icon': '🥗',
      'saved': false,
    },
    {
      'title': 'Info BPJS Kesehatan',
      'subtitle': 'Cara daftar, fasilitas, dan klaim',
      'icon': '🏥',
      'saved': false,
    },
    {
      'title': 'Gizi Balita',
      'subtitle': 'Kebutuhan nutrisi anak 0-5 tahun',
      'icon': '👶',
      'saved': false,
    },
    {
      'title': 'Mitos P3K yang Berbahaya',
      'subtitle': 'Fakta vs mitos penanganan darurat medis',
      'icon': '⚠️',
      'saved': false,
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edukasi Kesehatan', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari panduan kesehatan...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textGrey),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.navy.withValues(alpha: 0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.navy.withValues(alpha: 0.2)),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _articles.length,
              itemBuilder: (context, i) => _ArticleCard(
                article: _articles[i],
                onToggleSave: () => setState(() => _articles[i]['saved'] = !_articles[i]['saved']),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final Map<String, dynamic> article;
  final VoidCallback onToggleSave;

  const _ArticleCard({required this.article, required this.onToggleSave});

  @override
  Widget build(BuildContext context) {
    final saved = article['saved'] as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Text(article['icon'] as String, style: const TextStyle(fontSize: 32)),
        title: Text(
          article['title'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            article['subtitle'] as String,
            style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
          ),
        ),
        trailing: GestureDetector(
          onTap: onToggleSave,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: saved ? AppColors.navy : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.navy),
            ),
            child: Text(
              saved ? 'Tersimpan' : 'Simpan',
              style: TextStyle(
                fontSize: 11,
                color: saved ? Colors.white : AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        onTap: () {
          // TODO: Buka artikel detail dari sqflite
        },
      ),
    );
  }
}

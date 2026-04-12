import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/education_content_service.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final EducationContentService _contentService = EducationContentService();

  List<EducationArticle> _articles = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadArticles({String? query}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final articles = await _contentService.getArticles(
        query: query ?? _searchController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _articles = articles;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Konten edukasi lokal belum bisa dimuat: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleSave(EducationArticle article) async {
    final updatedArticle = await _contentService.toggleSaved(article.id);
    if (!mounted || updatedArticle == null) {
      return;
    }

    setState(() {
      _articles = _articles
          .map((item) => item.id == article.id ? updatedArticle : item)
          .toList();
    });
  }

  Future<void> _openArticle(EducationArticle article) async {
    _searchFocusNode.unfocus();
    final latestArticle = await _contentService.getArticleById(article.id);
    if (!mounted || latestArticle == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ArticleCategoryChip(label: latestArticle.category),
                  const SizedBox(height: 12),
                  if (latestArticle.id == 'edu-bpjs') ...[
                    Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppColors.urgencyGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.urgencyGreen.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.credit_card_outlined,
                            size: 48,
                            color: AppColors.urgencyGreen,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Kartu BPJS Kesehatan',
                            style: TextStyle(
                              color: AppColors.urgencyGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    latestArticle.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    latestArticle.subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textGrey,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.offline_bolt_rounded,
                        size: 18,
                        color: AppColors.navy,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tersedia offline • ${latestArticle.readTimeMinutes} menit baca',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    latestArticle.content,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textDark,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final savedCount = _articles.where((article) => article.isSaved).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edukasi Kesehatan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Cari panduan kesehatan...',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textGrey,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.navy.withValues(alpha: 0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.navy.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  onChanged: (_) => _loadArticles(),
                ),
                const SizedBox(height: 12),
                Text(
                  savedCount == 0
                      ? 'Konten lokal siap dipakai tanpa internet.'
                      : '$savedCount artikel ditandai tersimpan untuk dibaca lagi.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textGrey,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    if (_articles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Belum ada artikel yang cocok dengan kata kunci ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textGrey,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _articles.length,
      itemBuilder: (context, index) {
        final article = _articles[index];
        return _ArticleCard(
          article: article,
          onToggleSave: () => _toggleSave(article),
          onOpen: () => _openArticle(article),
        );
      },
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.article,
    required this.onToggleSave,
    required this.onOpen,
  });

  final EducationArticle article;
  final VoidCallback onToggleSave;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconForCategory(article.category),
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            article.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ArticleCategoryChip(label: article.category),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      article.subtitle,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '${article.readTimeMinutes} menit baca',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: onToggleSave,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: article.isSaved
                                  ? AppColors.navy
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.navy),
                            ),
                            child: Text(
                              article.isSaved ? 'Tersimpan' : 'Simpan',
                              style: TextStyle(
                                fontSize: 11,
                                color: article.isSaved
                                    ? Colors.white
                                    : AppColors.navy,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'p3k':
        return Icons.medical_services_outlined;
      case 'keluarga':
        return Icons.child_care_outlined;
      case 'layanan':
        return Icons.local_hospital_outlined;
      case 'mitos':
        return Icons.warning_amber_rounded;
      default:
        return Icons.menu_book_outlined;
    }
  }
}

class _ArticleCategoryChip extends StatelessWidget {
  const _ArticleCategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

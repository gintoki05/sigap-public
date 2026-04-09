import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class RagDocument {
  const RagDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.tags,
    required this.content,
    required this.source,
  });

  final String id;
  final String title;
  final String category;
  final List<String> tags;
  final String content;
  final String source;

  Map<String, Object?> toRow() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'tags': tags.join(','),
      'content': content,
      'source': source,
    };
  }

  static RagDocument fromRow(Map<String, Object?> row) {
    return RagDocument(
      id: row['id']! as String,
      title: row['title']! as String,
      category: row['category']! as String,
      tags: (row['tags']! as String)
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      content: row['content']! as String,
      source: row['source']! as String,
    );
  }
}

class RagSearchResult {
  const RagSearchResult({
    required this.document,
    required this.score,
    required this.strategy,
  });

  final RagDocument document;
  final double score;
  final String strategy;
}

class RagService extends ChangeNotifier {
  RagService._internal();

  static final RagService _instance = RagService._internal();

  factory RagService() => _instance;

  static const String _databaseName = 'sigap_rag.db';
  static const String _vectorStoreName = 'sigap_rag_vectors.db';
  static const String _tableKnowledgeBase = 'knowledge_base';

  Database? _database;
  bool _initialized = false;
  bool _vectorStoreInitialized = false;
  bool _vectorStoreSeeded = false;
  String _status = 'RAG belum diinisialisasi.';

  String get status => _status;
  bool get isInitialized => _initialized;
  bool get isVectorStoreReady => _vectorStoreInitialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _status = 'Menyiapkan basis pengetahuan lokal SIGAP...';
    notifyListeners();

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final databasePath = p.join(documentsDirectory.path, _databaseName);
    _database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_tableKnowledgeBase (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            tags TEXT NOT NULL,
            content TEXT NOT NULL,
            source TEXT NOT NULL
          )
        ''');
      },
    );

    await seedDatabase();
    await _initializeVectorStoreIfPossible(documentsDirectory.path);

    _initialized = true;
    _status = _vectorStoreInitialized
        ? 'RAG lokal siap dengan VectorStore.'
        : 'Basis pengetahuan lokal siap. Semantic search menunggu embedding model.';
    notifyListeners();
  }

  Future<void> seedDatabase() async {
    final db = await _requireDatabase();
    final existingCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_tableKnowledgeBase'),
    );
    if ((existingCount ?? 0) > 0) {
      return;
    }

    final batch = db.batch();
    for (final document in _seedDocuments) {
      batch.insert(
        _tableKnowledgeBase,
        document.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<String>> query(String input, {int limit = 3}) async {
    final results = await retrieve(input, limit: limit);
    return results.map((result) => result.document.content).toList();
  }

  Future<List<RagSearchResult>> retrieve(String input, {int limit = 3}) async {
    if (!_initialized) {
      await initialize();
    }

    if (_vectorStoreInitialized) {
      final vectorResults = await _searchVectorStore(input, limit: limit);
      if (vectorResults.isNotEmpty) {
        return vectorResults;
      }
    }

    return _searchLocalDatabase(input, limit: limit);
  }

  Future<List<RagSearchResult>> _searchVectorStore(
    String input, {
    required int limit,
  }) async {
    try {
      final results = await FlutterGemmaPlugin.instance.searchSimilar(
        query: input,
        topK: limit,
        threshold: 0.45,
      );

      return results
          .map((result) {
            final metadata = result.metadata == null
                ? const <String, dynamic>{}
                : jsonDecode(result.metadata!) as Map<String, dynamic>;
            return RagSearchResult(
              document: RagDocument(
                id: result.id,
                title: metadata['title'] as String? ?? result.id,
                category: metadata['category'] as String? ?? 'umum',
                tags: (metadata['tags'] as List<dynamic>? ?? const [])
                    .map((tag) => '$tag')
                    .toList(),
                content: result.content,
                source: metadata['source'] as String? ?? 'Internal SIGAP',
              ),
              score: result.similarity,
              strategy: 'vector',
            );
          })
          .toList();
    } catch (error) {
      debugPrint('[RagService] Vector search fallback: $error');
      return const [];
    }
  }

  Future<List<RagSearchResult>> _searchLocalDatabase(
    String input, {
    required int limit,
  }) async {
    final db = await _requireDatabase();
    final rows = await db.query(_tableKnowledgeBase);
    final tokens = _expandQueryTokens(input);

    final scored = rows
        .map(RagDocument.fromRow)
        .map((document) {
          final haystack = [
            document.title,
            document.category,
            document.tags.join(' '),
            document.content,
          ].join(' ').toLowerCase();

          var score = 0.0;
          for (final token in tokens) {
            if (haystack.contains(token)) {
              score += 1.0;
            }
            if (document.title.toLowerCase().contains(token)) {
              score += 1.2;
            }
            if (document.tags.any((tag) => tag.toLowerCase().contains(token))) {
              score += 0.8;
            }
          }

          return RagSearchResult(
            document: document,
            score: score,
            strategy: 'keyword',
          );
        })
        .where((result) => result.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isNotEmpty) {
      return scored.take(limit).toList();
    }

    return rows
        .take(limit)
        .map(RagDocument.fromRow)
        .map(
          (document) => RagSearchResult(
            document: document,
            score: 0,
            strategy: 'fallback',
          ),
        )
        .toList();
  }

  Future<void> _initializeVectorStoreIfPossible(String documentsPath) async {
    if (!FlutterGemma.hasActiveEmbedder()) {
      _status =
          'Embedding model belum aktif. SIGAP memakai keyword retrieval lokal dulu.';
      return;
    }

    try {
      await FlutterGemma.getActiveEmbedder(
        preferredBackend: PreferredBackend.cpu,
      );
      final vectorStorePath = p.join(documentsPath, _vectorStoreName);
      await FlutterGemmaPlugin.instance.initializeVectorStore(vectorStorePath);
      _vectorStoreInitialized = true;
      await _seedVectorStoreIfNeeded();
    } catch (error) {
      _vectorStoreInitialized = false;
      _status =
          'VectorStore belum siap dipakai. SIGAP tetap memakai retrieval lokal. Detail: $error';
    }
  }

  Future<void> _seedVectorStoreIfNeeded() async {
    if (!_vectorStoreInitialized || _vectorStoreSeeded) {
      return;
    }

    try {
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      if (stats.documentCount > 0) {
        _vectorStoreSeeded = true;
        return;
      }

      final embeddingModel = await FlutterGemma.getActiveEmbedder(
        preferredBackend: PreferredBackend.cpu,
      );
      final contents = _seedDocuments.map((document) => document.content).toList();
      final embeddings = await embeddingModel.generateEmbeddings(
        contents,
        taskType: TaskType.retrievalDocument,
      );

      for (var index = 0; index < _seedDocuments.length; index++) {
        final document = _seedDocuments[index];
        await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: document.id,
          content: document.content,
          embedding: embeddings[index],
          metadata: jsonEncode({
            'title': document.title,
            'category': document.category,
            'tags': document.tags,
            'source': document.source,
          }),
        );
      }
      _vectorStoreSeeded = true;
    } catch (error) {
      _vectorStoreInitialized = false;
      _status =
          'Seed VectorStore gagal. Retrieval lokal tetap tersedia. Detail: $error';
    }
  }

  Future<Database> _requireDatabase() async {
    final db = _database;
    if (db == null) {
      throw StateError('RAG database belum diinisialisasi.');
    }
    return db;
  }

  List<String> _tokenize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 3)
        .toList();
  }

  List<String> _expandQueryTokens(String input) {
    final baseTokens = _tokenize(input);
    final expanded = <String>{...baseTokens};

    for (final token in baseTokens) {
      expanded.addAll(_keywordAliases[token] ?? const []);
    }

    final normalizedInput = input.toLowerCase();
    for (final entry in _phraseAliases.entries) {
      if (normalizedInput.contains(entry.key)) {
        expanded.addAll(entry.value);
      }
    }

    return expanded.toList();
  }
}

const Map<String, List<String>> _keywordAliases = {
  'sayat': ['sayatan', 'tersayat', 'iris', 'teriris', 'luka'],
  'sayatan': ['sayat', 'tersayat', 'iris', 'teriris', 'luka'],
  'lecet': ['abrasi', 'tergores', 'gesek', 'luka'],
  'gores': ['tergores', 'lecet', 'abrasi', 'luka'],
  'berdarah': ['darah', 'pendarahan', 'perdarahan', 'luka'],
  'darah': ['berdarah', 'pendarahan', 'perdarahan'],
  'mimisan': ['hidung', 'darah', 'epistaksis'],
  'pingsan': ['tidak', 'sadar', 'lemas'],
  'kejang': ['epilepsi', 'kelojotan'],
  'tersedak': ['napas', 'sumbatan', 'batuk'],
  'bakar': ['terbakar', 'panas', 'knalpot'],
  'terbakar': ['bakar', 'panas', 'knalpot'],
  'fraktur': ['patah', 'tulang', 'cedera'],
  'patah': ['fraktur', 'tulang', 'cedera'],
  'listrik': ['sengatan', 'setrum'],
  'setrum': ['listrik', 'sengatan'],
  'ular': ['gigitan', 'bisa'],
  'keracunan': ['racun', 'muntah', 'tertelan'],
  'infeksi': ['nanah', 'merah', 'bengkak'],
};

const Map<String, List<String>> _phraseAliases = {
  'benda menancap': ['tertancap', 'asing', 'jangan', 'cabut'],
  'tidak sadar': ['pingsan', 'respons', 'napas'],
  'nyeri dada': ['sesak', 'jantung', 'darurat'],
  'gigitan serangga': ['gatal', 'bengkak', 'alergi'],
  'luka sayat': ['sayat', 'sayatan', 'berdarah'],
  'luka lecet': ['lecet', 'abrasi', 'tergores'],
  'patah tulang': ['fraktur', 'imobilisasi', 'cedera'],
};

final List<RagDocument> _seedDocuments = [
  const RagDocument(
    id: 'protocol-luka-sayat',
    title: 'Protokol P3K Luka Sayat Ringan',
    category: 'protokol',
    tags: ['luka sayat', 'sayatan', 'tersayat', 'berdarah'],
    content:
        'Untuk luka sayat ringan: cuci tangan bila memungkinkan, tekan luka dengan kain bersih atau kasa jika berdarah, bilas dengan air bersih mengalir, lalu tutup dengan balutan bersih. Cari bantuan medis bila luka dalam, lebar, sulit berhenti berdarah, atau berada di wajah, sendi, atau dekat tendon.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-luka-lecet',
    title: 'Protokol P3K Luka Lecet atau Abrasi',
    category: 'protokol',
    tags: ['luka lecet', 'abrasi', 'tergores', 'jatuh'],
    content:
        'Untuk luka lecet atau abrasi: bersihkan kotoran dengan air bersih mengalir, jangan gosok terlalu keras, hentikan perdarahan ringan dengan tekanan lembut, lalu tutup dengan kasa atau plester bersih. Periksa ke fasilitas kesehatan bila luka sangat kotor, luas, atau muncul tanda infeksi seperti bengkak, merah berat, atau nanah.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-luka-bakar',
    title: 'Protokol P3K Luka Bakar Ringan',
    category: 'protokol',
    tags: ['luka bakar', 'panas', 'knalpot', 'air mengalir'],
    content:
        'Untuk luka bakar ringan karena knalpot atau benda panas: jauhkan dari sumber panas, dinginkan dengan air mengalir suhu normal selama sekitar 20 menit, lepaskan benda ketat di sekitar luka bila tidak menempel, lalu tutup longgar dengan kasa atau kain bersih. Jangan pakai es, pasta gigi, mentega, kopi, atau minyak. Cari bantuan medis jika luka luas, mengenai wajah, tangan, alat kelamin, sendi besar, atau korban tampak lemah.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-perdarahan',
    title: 'Protokol P3K Pendarahan Luar',
    category: 'protokol',
    tags: ['pendarahan', 'luka', 'darah', 'tekan'],
    content:
        'Untuk pendarahan luar: tekan luka dengan kain bersih atau kasa, tinggikan area bila memungkinkan, dan jangan sering membuka balutan hanya untuk mengecek. Jika darah merembes, tambahkan lapisan baru di atasnya. Segera cari bantuan medis jika darah sangat banyak, tidak berhenti, atau korban tampak pucat dan lemah.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-tersedak',
    title: 'Protokol P3K Tersedak',
    category: 'protokol',
    tags: ['tersedak', 'napas', 'heimlich', 'batuk'],
    content:
        'Jika korban tersedak tetapi masih bisa batuk atau bicara, dorong untuk terus batuk. Jika tidak bisa bicara, bernapas, atau batuk efektif, minta bantuan segera dan lakukan pukulan punggung serta hentakan perut sesuai pedoman dasar. Jika korban tidak responsif, segera hubungi bantuan darurat.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-kejang',
    title: 'Protokol P3K Kejang',
    category: 'protokol',
    tags: ['kejang', 'epilepsi', 'miringkan', 'aman'],
    content:
        'Saat kejang: lindungi kepala korban, singkirkan benda berbahaya di sekitar, jangan menahan gerakan tubuh, jangan memasukkan benda ke mulut, dan setelah kejang berhenti miringkan korban bila memungkinkan agar jalan napas lebih aman. Cari bantuan medis bila kejang lama, berulang, atau korban tidak sadar penuh setelahnya.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-pingsan',
    title: 'Protokol P3K Pingsan',
    category: 'protokol',
    tags: ['pingsan', 'tidak sadar', 'napas', 'respon'],
    content:
        'Jika seseorang pingsan, cek respons dan napasnya, longgarkan pakaian ketat, dan posisikan aman. Bila tidak bernapas normal atau tidak responsif, ini gawat darurat dan butuh bantuan medis segera. Jangan memberi makan atau minum saat korban belum pulih sepenuhnya.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-mimisan',
    title: 'Protokol P3K Mimisan',
    category: 'protokol',
    tags: ['mimisan', 'hidung', 'darah', 'epistaksis'],
    content:
        'Untuk mimisan: dudukkan korban tegak dan condong sedikit ke depan, tekan bagian lunak hidung selama sekitar 10 menit tanpa sering melepas tekanan, dan minta korban bernapas lewat mulut. Cari bantuan medis bila perdarahan berat, tidak berhenti, atau terjadi setelah benturan keras.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-benda-menancap',
    title: 'Protokol P3K Bila Ada Benda Menancap',
    category: 'protokol',
    tags: ['benda menancap', 'tertancap', 'asing', 'jangan cabut'],
    content:
        'Jika ada benda menancap pada luka, jangan cabut benda tersebut. Stabilkan area di sekitarnya dengan kain atau balutan seperlunya, tekan perdarahan di sekitar luka bila memungkinkan tanpa menekan benda, dan segera cari bantuan medis.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-stroke',
    title: 'Tanda Darurat Stroke',
    category: 'protokol',
    tags: ['stroke', 'wajah pelo', 'bicara pelo', 'lemah sebelah'],
    content:
        'Jika ada wajah mencong, lengan mendadak lemah, atau bicara pelo, anggap sebagai stroke sampai terbukti bukan. Catat waktu mulai gejala dan segera cari bantuan medis. Jangan menunda dengan pijat, kerokan, atau obat sembarangan.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-nyeri-dada',
    title: 'Tanda Gawat Nyeri Dada',
    category: 'protokol',
    tags: ['nyeri dada', 'sesak', 'jantung', 'darurat'],
    content:
        'Nyeri dada berat, terutama disertai sesak, keringat dingin, lemas, atau menjalar ke lengan atau rahang, harus dianggap gawat darurat. Hentikan aktivitas, bantu korban duduk nyaman, dan segera cari bantuan medis.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-fraktur',
    title: 'Protokol P3K Cedera Diduga Patah Tulang',
    category: 'protokol',
    tags: ['fraktur', 'patah tulang', 'imobilisasi', 'cedera'],
    content:
        'Jika diduga patah tulang, jangan paksa meluruskan anggota tubuh yang cedera. Kurangi gerakan, imobilisasi pada posisi yang ditemukan bila mampu dan aman, kompres dingin terbungkus kain untuk bengkak bila perlu, dan segera cari bantuan medis terutama bila nyeri berat, bentuk anggota tubuh berubah, atau korban tidak bisa menggerakkan bagian tersebut.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-gigitan-serangga',
    title: 'Protokol P3K Gigitan atau Sengatan Serangga',
    category: 'protokol',
    tags: ['gigitan serangga', 'sengatan', 'gatal', 'bengkak'],
    content:
        'Untuk gigitan atau sengatan serangga ringan: bersihkan area dengan air dan sabun lembut, kompres dingin dengan kain, dan pantau bengkak atau gatal. Cari bantuan medis segera bila muncul sesak, bengkak luas, pusing, muntah, atau reaksi alergi berat.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-sengatan-listrik',
    title: 'Protokol P3K Sengatan Listrik',
    category: 'protokol',
    tags: ['sengatan listrik', 'setrum', 'arus', 'bahaya'],
    content:
        'Pada sengatan listrik, pastikan sumber listrik sudah aman sebelum menyentuh korban. Setelah aman, cek respons dan napas, dan cari bantuan medis karena cedera dalam bisa terjadi walau luka luar tampak kecil. Jika korban tidak responsif atau tidak bernapas normal, anggap gawat darurat.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'protocol-keracunan',
    title: 'Protokol Awal Kecurigaan Keracunan',
    category: 'protokol',
    tags: ['keracunan', 'racun', 'tertelan', 'muntah'],
    content:
        'Bila dicurigai keracunan, jauhkan korban dari sumber paparan bila aman, identifikasi zat yang mungkin terlibat, dan jangan memaksa muntah kecuali diarahkan tenaga medis. Segera cari bantuan medis terutama bila korban sesak, kejang, muntah terus, atau penurunan kesadaran.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-burn-toothpaste',
    title: 'Mitos: Pasta gigi untuk luka bakar',
    category: 'mitos',
    tags: ['mitos', 'pasta gigi', 'luka bakar'],
    content:
        'Mitos berbahaya: pasta gigi membantu menyembuhkan luka bakar. Koreksi: pasta gigi bukan penanganan luka bakar, bisa mengiritasi kulit, dan menyulitkan pembersihan luka. Luka bakar ringan sebaiknya didinginkan dengan air mengalir suhu normal.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-burn-butter',
    title: 'Mitos: Mentega atau minyak untuk luka bakar',
    category: 'mitos',
    tags: ['mitos', 'mentega', 'minyak', 'luka bakar'],
    content:
        'Mitos berbahaya: mentega atau minyak menenangkan luka bakar. Koreksi: bahan berminyak dapat menahan panas di kulit dan mengganggu perawatan luka. Gunakan air mengalir dan penutup bersih non lengket.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-burn-ice',
    title: 'Mitos: Es langsung pada luka bakar',
    category: 'mitos',
    tags: ['mitos', 'es', 'luka bakar'],
    content:
        'Mitos berbahaya: es langsung mempercepat penyembuhan luka bakar. Koreksi: es dapat memperparah kerusakan jaringan. Pakai air mengalir suhu normal, bukan air es.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-bleeding-coffee',
    title: 'Mitos: Bubuk kopi pada luka berdarah',
    category: 'mitos',
    tags: ['mitos', 'kopi', 'luka', 'darah'],
    content:
        'Mitos berbahaya: bubuk kopi menghentikan pendarahan. Koreksi: bubuk kopi dapat mengotori luka dan meningkatkan risiko infeksi. Penanganan awal yang benar adalah tekan luka dengan kain bersih atau kasa.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-bleeding-soil',
    title: 'Mitos: Tanah atau abu pada luka',
    category: 'mitos',
    tags: ['mitos', 'tanah', 'abu', 'infeksi'],
    content:
        'Mitos berbahaya: tanah atau abu membantu menutup luka. Koreksi: bahan kotor sangat meningkatkan risiko infeksi. Gunakan penekanan langsung dengan bahan bersih.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-nosebleed-headback',
    title: 'Mitos: Mimisan ditangani dengan mendongak',
    category: 'mitos',
    tags: ['mitos', 'mimisan', 'mendongak'],
    content:
        'Mitos berbahaya: kepala harus didongakkan saat mimisan. Koreksi: posisi ini membuat darah mengalir ke tenggorokan. Penanganan awal yang benar adalah duduk condong sedikit ke depan sambil menekan bagian lunak hidung.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-seizure-spoon',
    title: 'Mitos: Sendok ke mulut saat kejang',
    category: 'mitos',
    tags: ['mitos', 'kejang', 'sendok', 'mulut'],
    content:
        'Mitos berbahaya: masukkan sendok atau benda keras ke mulut orang kejang. Koreksi: ini bisa melukai gigi, mulut, dan penolong. Fokuslah melindungi kepala dan area sekitar.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-seizure-hold',
    title: 'Mitos: Tahan tubuh korban saat kejang',
    category: 'mitos',
    tags: ['mitos', 'kejang', 'tahan tubuh'],
    content:
        'Mitos berbahaya: tubuh korban kejang harus ditahan kuat-kuat. Koreksi: menahan tubuh dapat menyebabkan cedera. Amankan lingkungan sekitar dan tunggu kejang mereda.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-fainting-water',
    title: 'Mitos: Langsung beri minum saat pingsan',
    category: 'mitos',
    tags: ['mitos', 'pingsan', 'beri minum'],
    content:
        'Mitos berbahaya: orang pingsan harus langsung diberi minum. Koreksi: ini berisiko tersedak bila korban belum sadar penuh. Cek napas dan respons terlebih dahulu.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-stroke-massage',
    title: 'Mitos: Stroke diatasi dengan pijat',
    category: 'mitos',
    tags: ['mitos', 'stroke', 'pijat'],
    content:
        'Mitos berbahaya: stroke cukup diurut atau dipijat dulu. Koreksi: stroke adalah keadaan darurat medis dan butuh penanganan cepat di fasilitas kesehatan. Menunda penanganan dapat memperburuk hasil.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-heartburn-kerokan',
    title: 'Mitos: Nyeri dada cukup dikerok',
    category: 'mitos',
    tags: ['mitos', 'nyeri dada', 'kerokan'],
    content:
        'Mitos berbahaya: nyeri dada berat cukup dikerok atau dipijat. Koreksi: nyeri dada bisa menandakan gangguan jantung atau paru dan perlu evaluasi medis segera.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-choking-water',
    title: 'Mitos: Orang tersedak diberi minum',
    category: 'mitos',
    tags: ['mitos', 'tersedak', 'minum'],
    content:
        'Mitos berbahaya: korban tersedak langsung diberi air minum. Koreksi: ini bisa memperparah sumbatan. Nilai dulu apakah korban masih bisa batuk atau bernapas.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-snake-tourniquet',
    title: 'Mitos: Gigitan ular harus dipasang torniket keras',
    category: 'mitos',
    tags: ['mitos', 'ular', 'torniket'],
    content:
        'Mitos berbahaya: gigitan ular selalu ditangani dengan torniket yang sangat kencang. Koreksi: tindakan ini bisa merusak jaringan. Korban sebaiknya ditenangkan, area digerakkan seminimal mungkin, dan segera cari bantuan medis.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-snake-suck',
    title: 'Mitos: Bisa ular disedot keluar',
    category: 'mitos',
    tags: ['mitos', 'ular', 'sedot bisa'],
    content:
        'Mitos berbahaya: bisa ular harus disedot dengan mulut. Koreksi: tindakan ini tidak terbukti membantu dan berisiko bagi penolong. Fokus pada imobilisasi dan rujukan medis.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-fracture-straighten',
    title: 'Mitos: Tulang patah harus langsung diluruskan',
    category: 'mitos',
    tags: ['mitos', 'fraktur', 'patah tulang'],
    content:
        'Mitos berbahaya: tulang yang tampak patah harus segera ditarik lurus. Koreksi: manipulasi bisa memperparah cedera. Imobilisasi posisi yang ditemukan dan cari pertolongan medis.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-burn-pop-blister',
    title: 'Mitos: Lepuh luka bakar harus dipecahkan',
    category: 'mitos',
    tags: ['mitos', 'lepuh', 'luka bakar'],
    content:
        'Mitos berbahaya: lepuh luka bakar harus segera dipecahkan. Koreksi: lepuh membantu melindungi jaringan di bawahnya. Biarkan tetap utuh dan tutup longgar bila perlu.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-poison-vomit',
    title: 'Mitos: Keracunan selalu dipaksa muntah',
    category: 'mitos',
    tags: ['mitos', 'keracunan', 'muntah'],
    content:
        'Mitos berbahaya: semua keracunan harus dipaksa muntah. Koreksi: beberapa zat justru lebih berbahaya bila dimuntahkan kembali. Cari bantuan medis atau pusat informasi racun sesuai konteks lokal.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-shock-slapped',
    title: 'Mitos: Orang lemas harus ditampar keras',
    category: 'mitos',
    tags: ['mitos', 'lemas', 'tampar'],
    content:
        'Mitos berbahaya: korban lemas atau hampir pingsan perlu ditampar keras agar sadar. Koreksi: fokuslah pada keamanan posisi, penilaian napas, dan penyebab yang mendasari.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-burn-soy-sauce',
    title: 'Mitos: Kecap atau bahan dapur untuk luka bakar',
    category: 'mitos',
    tags: ['mitos', 'kecap', 'luka bakar', 'bahan dapur'],
    content:
        'Mitos berbahaya: kecap, minyak, atau bahan dapur lain aman untuk luka bakar. Koreksi: bahan tersebut tidak steril dan bisa memperburuk luka. Gunakan air mengalir suhu normal sebagai langkah awal.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-bite-garlic',
    title: 'Mitos: Bawang untuk gigitan serangga',
    category: 'mitos',
    tags: ['mitos', 'gigitan serangga', 'bawang'],
    content:
        'Mitos berbahaya: bawang atau bahan iritatif harus dioles pada gigitan serangga. Koreksi: ini bisa menambah iritasi kulit. Bersihkan area dan pantau tanda reaksi berat seperti sesak atau bengkak luas.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-electrocution-touch',
    title: 'Mitos: Korban sengatan listrik langsung disentuh',
    category: 'mitos',
    tags: ['mitos', 'listrik', 'sengatan'],
    content:
        'Mitos berbahaya: korban sengatan listrik boleh langsung disentuh untuk dipindahkan. Koreksi: pastikan sumber listrik sudah aman lebih dulu agar penolong tidak ikut tersengat.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-epistaxis-lie-down',
    title: 'Mitos: Mimisan ditangani sambil telentang',
    category: 'mitos',
    tags: ['mitos', 'mimisan', 'telentang'],
    content:
        'Mitos berbahaya: korban mimisan sebaiknya telentang. Koreksi: posisi ini membuat darah mengalir ke tenggorokan. Duduk tegak dan condong sedikit ke depan lebih aman.',
    source: 'Ringkasan internal SIGAP',
  ),
  const RagDocument(
    id: 'myth-fever-alcohol',
    title: 'Mitos: Alkohol di seluruh tubuh untuk demam tinggi',
    category: 'mitos',
    tags: ['mitos', 'demam', 'alkohol'],
    content:
        'Mitos berbahaya: alkohol harus dioles banyak ke tubuh untuk menurunkan demam. Koreksi: ini bisa mengiritasi kulit dan tidak menangani penyebabnya. Pantau gejala berat dan cari bantuan medis bila perlu.',
    source: 'Ringkasan internal SIGAP',
  ),
];

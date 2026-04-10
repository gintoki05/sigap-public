import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class EducationArticle {
  const EducationArticle({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.readTimeMinutes,
    required this.content,
    required this.isSaved,
  });

  final String id;
  final String title;
  final String subtitle;
  final String category;
  final int readTimeMinutes;
  final String content;
  final bool isSaved;

  EducationArticle copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? category,
    int? readTimeMinutes,
    String? content,
    bool? isSaved,
  }) {
    return EducationArticle(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      category: category ?? this.category,
      readTimeMinutes: readTimeMinutes ?? this.readTimeMinutes,
      content: content ?? this.content,
      isSaved: isSaved ?? this.isSaved,
    );
  }

  factory EducationArticle.fromRow(Map<String, Object?> row) {
    return EducationArticle(
      id: row['id']! as String,
      title: row['title']! as String,
      subtitle: row['subtitle']! as String,
      category: row['category']! as String,
      readTimeMinutes: row['read_time_minutes']! as int,
      content: row['content']! as String,
      isSaved: (row['is_saved']! as int) == 1,
    );
  }
}

class EducationContentService {
  EducationContentService._internal();

  static final EducationContentService _instance =
      EducationContentService._internal();

  factory EducationContentService() => _instance;

  static const String _databaseName = 'sigap_education.db';
  static const String _tableArticles = 'education_articles';

  Database? _database;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final databasePath = p.join(documentsDirectory.path, _databaseName);
    _database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_tableArticles (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            category TEXT NOT NULL,
            read_time_minutes INTEGER NOT NULL,
            content TEXT NOT NULL,
            is_saved INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );

    await _seedArticlesIfNeeded();
    _isInitialized = true;
  }

  Future<List<EducationArticle>> getArticles({String query = ''}) async {
    await initialize();
    final db = _requireDatabase();
    final trimmedQuery = query.trim().toLowerCase();

    if (trimmedQuery.isEmpty) {
      final rows = await db.query(
        _tableArticles,
        orderBy: 'is_saved DESC, title COLLATE NOCASE ASC',
      );
      return rows.map(EducationArticle.fromRow).toList();
    }

    final rows = await db.query(
      _tableArticles,
      where: '''
        lower(title) LIKE ? OR
        lower(subtitle) LIKE ? OR
        lower(category) LIKE ? OR
        lower(content) LIKE ?
      ''',
      whereArgs: List.filled(4, '%$trimmedQuery%'),
      orderBy: 'is_saved DESC, title COLLATE NOCASE ASC',
    );
    return rows.map(EducationArticle.fromRow).toList();
  }

  Future<EducationArticle?> getArticleById(String id) async {
    await initialize();
    final db = _requireDatabase();
    final rows = await db.query(
      _tableArticles,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return EducationArticle.fromRow(rows.first);
  }

  Future<EducationArticle?> toggleSaved(String id) async {
    await initialize();
    final article = await getArticleById(id);
    if (article == null) {
      return null;
    }

    final nextValue = article.isSaved ? 0 : 1;
    final db = _requireDatabase();
    await db.update(
      _tableArticles,
      {'is_saved': nextValue},
      where: 'id = ?',
      whereArgs: [id],
    );
    return article.copyWith(isSaved: nextValue == 1);
  }

  Database _requireDatabase() {
    final database = _database;
    if (database == null) {
      throw StateError('Education database belum siap.');
    }
    return database;
  }

  Future<void> _seedArticlesIfNeeded() async {
    final db = _requireDatabase();
    final existingCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_tableArticles'),
    );
    if ((existingCount ?? 0) > 0) {
      return;
    }

    final batch = db.batch();
    for (final article in _seedArticles) {
      batch.insert(_tableArticles, {
        'id': article.id,
        'title': article.title,
        'subtitle': article.subtitle,
        'category': article.category,
        'read_time_minutes': article.readTimeMinutes,
        'content': article.content,
        'is_saved': article.isSaved ? 1 : 0,
      });
    }
    await batch.commit(noResult: true);
  }
}

const List<EducationArticle> _seedArticles = [
  EducationArticle(
    id: 'edu-p3k-dasar',
    title: 'P3K Dasar',
    subtitle: 'Panduan awal pertolongan pertama untuk warga awam.',
    category: 'P3K',
    readTimeMinutes: 4,
    isSaved: false,
    content:
        'P3K dasar dimulai dari memastikan lokasi aman, menilai respons korban, lalu mengamankan ancaman paling berbahaya seperti perdarahan hebat atau gangguan napas. Gunakan sarung tangan atau kain bersih bila ada. Jangan memberi makan atau minum pada korban yang menurun kesadarannya. Jika gejala berat, segera cari bantuan medis sambil mengikuti panduan AI atau protokol dasar.',
  ),
  EducationArticle(
    id: 'edu-stunting',
    title: 'Pencegahan Stunting',
    subtitle: 'Kebiasaan sederhana untuk mendukung tumbuh kembang anak.',
    category: 'Keluarga',
    readTimeMinutes: 3,
    isSaved: false,
    content:
        'Pencegahan stunting berfokus pada gizi ibu sejak hamil, ASI eksklusif, makanan pendamping yang cukup protein, imunisasi, kebersihan air, dan pemantauan pertumbuhan anak. Bila berat badan atau tinggi anak tampak tidak sesuai usianya, konsultasikan ke puskesmas atau tenaga kesehatan terdekat untuk evaluasi lebih lanjut.',
  ),
  EducationArticle(
    id: 'edu-bpjs',
    title: 'Info BPJS Kesehatan',
    subtitle: 'Ringkasan layanan dasar, rujukan, dan manfaat yang perlu diketahui.',
    category: 'Layanan',
    readTimeMinutes: 3,
    isSaved: false,
    content:
        'BPJS Kesehatan membantu akses layanan berjenjang mulai dari fasilitas kesehatan tingkat pertama hingga rujukan. Simpan nomor kepesertaan, cek faskes terdaftar, dan pahami kondisi darurat yang memungkinkan penanganan langsung di IGD. Untuk kebutuhan administrasi, siapkan identitas, kartu peserta, dan dokumen pendukung yang relevan.',
  ),
  EducationArticle(
    id: 'edu-gizi-balita',
    title: 'Gizi Balita',
    subtitle: 'Nutrisi penting untuk anak usia 0 sampai 5 tahun.',
    category: 'Keluarga',
    readTimeMinutes: 4,
    isSaved: false,
    content:
        'Gizi balita perlu seimbang antara karbohidrat, protein, lemak sehat, sayur, buah, dan cairan. Variasikan sumber protein seperti telur, ikan, ayam, tempe, dan tahu. Bila anak sulit makan terus-menerus, berat badan tidak naik, atau tampak lemas, lakukan konsultasi agar kebutuhan gizinya dievaluasi lebih lanjut.',
  ),
  EducationArticle(
    id: 'edu-mitos-p3k',
    title: 'Mitos P3K yang Berbahaya',
    subtitle: 'Koreksi kebiasaan umum yang justru bisa memperparah kondisi korban.',
    category: 'Mitos',
    readTimeMinutes: 5,
    isSaved: false,
    content:
        'Contoh mitos yang perlu dihindari: pasta gigi untuk luka bakar, kopi untuk luka berdarah, memberi minum saat tersedak, atau memasukkan sendok ke mulut orang kejang. Penanganan awal yang benar harus menjaga jalan napas, menghentikan perdarahan, dan mendinginkan luka bakar dengan air mengalir suhu normal bila sesuai kondisi.',
  ),
];

// TODO PRI-51: Implementasi setelah model Gemma 4 E4B didownload
// Setup flutter_gemma: GemmaManager + InferenceModel
// Enable GPU acceleration via LiteRT delegation
// Target latency: < 5 detik di device mid-range dengan GPU

class GemmaService {
  static final GemmaService _instance = GemmaService._internal();
  factory GemmaService() => _instance;
  GemmaService._internal();

  bool get isReady => false; // TODO: cek status model

  Future<void> initialize() async {
    // TODO: Load model dari file lokal
  }

  Stream<String> generateResponse(String prompt) async* {
    // TODO: Streaming inference via flutter_gemma
    yield 'Model belum siap. Selesaikan PRI-51.';
  }

  Future<void> dispose() async {
    // TODO: Release model resources
  }
}

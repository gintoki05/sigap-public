# SIGAP

SIGAP adalah aplikasi Flutter Android-first untuk pertolongan pertama darurat berbasis AI on-device. Untuk fase hackathon saat ini, SIGAP tetap **offline-first** dengan dua opsi model lokal Gemma 4 menggunakan `flutter_gemma` dan artefak **LiteRT-LM `.litertlm`**.

## Model Strategy

- Model rekomendasi setup awal: `Gemma 4 E2B-IT`
- Model alternatif kualitas demo lebih tinggi: `Gemma 4 E4B-IT`
- Format resmi runtime: `.litertlm`
- Alur produk: `download once, use offline forever`
- Cloud Assist belum diaktifkan di kode produksi hackathon; itu disimpan sebagai roadmap setelah demo offline tervalidasi

Jangan pakai repo `Transformers`/`safetensors` seperti `google/gemma-4-E4B-it` atau `google/gemma-4-E2B-it` sebagai artefak final untuk app ini. Untuk SIGAP, sumber model yang benar adalah repo LiteRT Community:

- E2B model card: `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm`
- E2B file: `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm`
- E4B model card: `https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm`
- E4B file: `https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm`

## Running The App

### Product-like flow

SIGAP sekarang default ke flow download model sekali lalu simpan di perangkat. Di UI, user bisa memilih:

- `Gemma 4 E2B-IT` sebagai opsi rekomendasi untuk setup awal
- `Gemma 4 E4B-IT` sebagai opsi kualitas demo lebih tinggi

Jika Anda tidak memberi URL custom, service akan memakai URL default LiteRT Community sesuai model yang dipilih user.

```powershell
flutter run
```

Atau bila ingin override URL model yang sedang dipilih:

```powershell
flutter run "--dart-define=SIGAP_GEMMA_MODEL_URL=https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
```

Jika repo model butuh autentikasi:

```powershell
flutter run "--dart-define=SIGAP_GEMMA_MODEL_AUTH_TOKEN=hf_xxx"
```

### Developer shortcut

Untuk development, hindari redownload model berulang-ulang. Gunakan model yang sudah ada di storage Android/device, bukan path `C:\...` milik host Windows.

Contoh path Android untuk file yang sudah Anda salin ke device:

```powershell
flutter run "--dart-define=SIGAP_GEMMA_MODEL_PATH=/sdcard/Download/gemma-4-E4B-it.litertlm"
```

Catatan:

- path Windows host tidak bisa langsung dibaca oleh runtime Android
- jika ingin memakai file yang sudah Anda download di Windows, salin dulu ke emulator/device
- app akan mencoba GPU dulu, lalu fallback ke CPU
- roadmap cloud/default saat ada koneksi belum diimplementasikan; sengaja ditunda sampai fase setelah hackathon

## References

- `flutter_gemma`: `https://pub.dev/packages/flutter_gemma`
- LiteRT-LM docs: `https://ai.google.dev/edge/litert-lm`
- Agent workflow guardrails: [`AGENTS.md`](/c:/Users/ajiep/Documents/Developments/Ajie/sigap/AGENTS.md)

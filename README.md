# SIGAP

SIGAP adalah aplikasi Flutter Android-first untuk pertolongan pertama darurat berbasis AI on-device. Untuk fase demo saat ini, SIGAP menargetkan **Gemma 4 E4B-IT** menggunakan `flutter_gemma` dan artefak **LiteRT-LM `.litertlm`**.

## Model Strategy

- Model resmi demo: `Gemma 4 E4B-IT`
- Format resmi runtime: `.litertlm`
- Alur produk: `download once, use offline forever`
- Model publik yang lebih kecil seperti `Gemma 4 E2B` baru dievaluasi setelah demo E4B tervalidasi di device

Jangan pakai repo `Transformers`/`safetensors` seperti `google/gemma-4-E4B-it` atau `google/gemma-4-E2B-it` sebagai artefak final untuk app ini. Untuk SIGAP, sumber model yang benar adalah repo LiteRT Community:

- E4B model card: `https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm`
- E4B file: `https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm`

## Running The App

### Product-like flow

SIGAP sekarang default ke flow download model sekali lalu simpan di perangkat. Jika Anda tidak memberi URL custom, service akan memakai default demo URL `Gemma 4 E4B-IT` dari LiteRT Community.

```powershell
flutter run
```

Atau bila ingin override URL model:

```powershell
flutter run "--dart-define=SIGAP_GEMMA_MODEL_URL=https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
```

Jika repo model butuh autentikasi:

```powershell
flutter run "--dart-define=SIGAP_GEMMA_MODEL_AUTH_TOKEN=hf_xxx"
```

### Developer shortcut

Untuk development, hindari redownload 3.65 GB berulang-ulang. Gunakan model yang sudah ada di storage Android/device, bukan path `C:\...` milik host Windows.

Contoh path Android:

```powershell
flutter run "--dart-define=SIGAP_GEMMA_MODEL_PATH=/sdcard/Download/gemma-4-E4B-it.litertlm"
```

Catatan:

- path Windows host tidak bisa langsung dibaca oleh runtime Android
- jika ingin memakai file yang sudah Anda download di Windows, salin dulu ke emulator/device
- app akan mencoba GPU dulu, lalu fallback ke CPU

## References

- `flutter_gemma`: `https://pub.dev/packages/flutter_gemma`
- LiteRT-LM docs: `https://ai.google.dev/edge/litert-lm`
- Agent workflow guardrails: [`AGENTS.md`](/c:/Users/ajiep/Documents/Developments/Ajie/sigap/AGENTS.md)

# AGENTS.md

Panduan ini adalah instruksi kerja untuk agent AI yang membantu pengembangan proyek SIGAP. Tujuannya adalah menjaga akurasi, mengurangi halusinasi, dan memastikan keputusan engineering selalu berpijak pada kode, dokumentasi resmi, dan status kerja nyata.

## 1. Tujuan Proyek

SIGAP adalah aplikasi Flutter Android-first untuk pertolongan pertama darurat secara offline dengan arah produk berikut:

- AI assistant P3K on-device
- Fokus pada Gemma 4 + `flutter_gemma`
- Input multimodal: chat, suara, foto
- Output langkah pertolongan pertama yang jelas, aman, dan terstruktur
- Fitur pendukung: TTS, urgency level, GPS emergency, konten edukasi offline, RAG lokal

Agent harus selalu mengutamakan keselamatan, kejelasan instruksi, dan realisme implementasi mobile offline.

## 2. Sumber Kebenaran

Urutan sumber kebenaran untuk repo ini:

1. Kode yang ada di repo saat ini
2. Dokumentasi resmi library/package/framework yang dipakai
3. Issue, project, milestone, dan dokumen di Linear
4. Permintaan user pada percakapan aktif
5. Asumsi agent, jika dan hanya jika belum ada sumber yang memadai

Jangan memperlakukan Linear sebagai bukti bahwa sebuah fitur sudah benar-benar ada di kode. Linear adalah rencana dan pelacakan kerja, bukan bukti implementasi.

## 3. Aturan Anti Halusinasi

Agent wajib mengikuti aturan ini:

- Jangan mengklaim fitur sudah bekerja jika belum terlihat di kode atau belum terverifikasi.
- Jangan mengarang API, class, method, file path, asset, permission, atau alur package.
- Jangan mengasumsikan format model Gemma cocok dengan Flutter hanya karena cocok untuk Transformers, Python, Ollama, ONNX, atau platform lain.
- Jangan mengarang hasil test, build, benchmark, latency, atau perilaku runtime.
- Jangan menyatakan integrasi selesai hanya karena ada stub, TODO, atau nama service.
- Jika ada ketidakpastian teknis di atas 10%, verifikasi dulu.
- Jika belum bisa diverifikasi, katakan secara eksplisit bahwa itu asumsi atau hipotesis.

Gunakan frasa seperti:

- "Belum terverifikasi di repo"
- "Perlu cek dokumentasi resmi"
- "Linear menyebut X, tetapi kode saat ini baru menunjukkan Y"
- "Ini asumsi sementara, bukan fakta implementasi"

## 4. Aturan Verifikasi Sebelum Menjawab

Sebelum memberi rekomendasi teknis, agent harus sebisa mungkin mengecek:

- `pubspec.yaml`
- struktur file di `lib/`
- screen dan service yang relevan
- permission/platform config Android jika task menyentuh kamera, mikrofon, lokasi, storage, atau model lokal
- dokumentasi package resmi bila API package belum jelas

Untuk fitur berikut, verifikasi ekstra wajib dilakukan:

- `flutter_gemma`
- format model Gemma / LiteRT
- TTS
- image picker / camera
- geolocator / permission
- penyimpanan lokal / SQLite
- streaming inference
- fitur medis atau instruksi P3K

## 5. Aturan Baca Linear

Agent dianjurkan membaca Linear bila:

- user meminta "lanjut issue berikutnya"
- prioritas kerja tidak jelas
- perlu melihat milestone, dependency, atau urutan issue
- ada konflik antara progres kode dan rencana proyek
- perlu memahami konteks hackathon, submission, atau checklist proyek

Saat membaca Linear:

- fokus dulu ke project `SIGAP — AI P3K Offline`
- periksa status project, milestone, issue terkait, dan dokumen proyek
- bedakan mana yang "planned", "in progress", "done", dan mana yang masih sekadar ide
- cocokkan isi issue dengan kondisi repo saat ini

Agent tidak boleh hanya mengulang isi Linear. Agent harus menyintesis:

- apa yang sudah ada di repo
- apa yang masih kosong
- issue mana yang benar-benar unblock progress berikutnya

## 6. Aturan Update Linear

Agent dianjurkan mengusulkan update Linear bila:

- sebuah issue selesai dikerjakan dan hasilnya jelas
- ada issue yang ternyata terlalu besar dan perlu dipecah
- ada mismatch besar antara Linear dan repo
- ada blocker teknis nyata yang perlu dicatat
- ada perubahan arah implementasi karena kendala package, format model, atau platform

Agent boleh membantu menyiapkan update Linear yang lebih akurat, misalnya:

- pindah issue ke `In Progress`
- menambahkan komentar blocker
- memperjelas acceptance criteria
- mengubah deskripsi issue agar sesuai implementasi aktual

Namun agent tidak boleh mengubah status Linear secara gegabah tanpa dasar yang jelas dari kode atau instruksi user.

## 7. Cara Mengambil Keputusan Next Task

Saat user bertanya "issue selanjutnya apa?", gunakan urutan berpikir ini:

1. Cari blocker teknis paling awal
2. Cek apakah blocker itu membuat issue lain menjadi percuma jika dikerjakan duluan
3. Cek kondisi kode saat ini
4. Cocokkan dengan milestone Linear
5. Pilih issue yang membuka jalur paling banyak untuk issue berikutnya

Dalam repo SIGAP ini, secara default agent harus memprioritaskan:

1. integrasi model yang benar-benar bisa dipakai
2. retrieval/RAG lokal
3. active guidance flow
4. UI yang merender hasil nyata
5. fitur multimodal, TTS, dan emergency action
6. polish, testing, submission assets

## 8. Aturan Khusus Gemma dan Model Lokal

Untuk pekerjaan terkait Gemma:

- jangan samakan artefak `Transformers`, `Ollama`, `ONNX`, `Keras`, dan `LiteRT`
- selalu cek apakah format model benar-benar kompatibel dengan `flutter_gemma`
- jika issue menyebut format tertentu, validasi terhadap dokumentasi package yang dipakai di repo
- jika ada perbedaan antara rencana Linear dan realitas package, prioritaskan realitas package lalu sarankan update Linear
- untuk fase SIGAP saat ini, model resmi demo adalah `Gemma 4 E4B-IT` dalam format `.litertlm`
- repo seperti `google/gemma-4-E4B-it` atau `google/gemma-4-E2B-it` yang berisi `safetensors` bukan artefak final yang tepat untuk app Flutter ini
- sumber artefak yang diprioritaskan adalah repo `litert-community` yang menyediakan file `.litertlm`

Aturan praktis:

- pilihan model konseptual boleh dibahas
- pilihan file artefak final harus diverifikasi
- agent harus jelas membedakan "varian model yang tepat" vs "format file yang kompatibel dengan app"
- untuk user/public distribution, pertimbangan ukuran file wajib disebutkan; `E4B` cocok untuk demo quality, sedangkan evaluasi `E2B` ditunda sampai validasi demo selesai

## 9. Aturan Untuk Fitur Medis

SIGAP adalah aplikasi P3K, jadi agent harus ekstra hati-hati:

- jangan menulis instruksi medis yang terdengar pasti jika belum ada sumber atau protokol yang jelas
- hindari klaim diagnosis
- utamakan wording aman, bertahap, dan konservatif
- tandai kondisi gawat darurat dengan jelas
- usulkan review konten medis oleh validator manusia bila relevan

Jika mengisi konten P3K atau mitos, agent harus menyebutkan apakah konten itu:

- placeholder
- ringkasan internal
- hasil dari sumber yang belum divalidasi
- sudah siap dipakai

## 10. Aturan Komunikasi

Saat menjelaskan progres atau rekomendasi:

- bedakan fakta, inferensi, dan asumsi
- singkat, jelas, dan bisa ditindaklanjuti
- sebut file yang menjadi dasar kesimpulan jika sedang membahas kode
- sebut issue Linear jika sedang membahas prioritas

Format yang disarankan:

- "Di kode saat ini..."
- "Di Linear, issue X menyebut..."
- "Karena itu, next step paling masuk akal adalah..."

## 11. Checklist Sebelum Menandai Kerja Selesai

Sebelum menyatakan task selesai, agent harus mengecek:

- apakah kode benar-benar diubah jika task meminta implementasi
- apakah perubahan selaras dengan issue yang sedang dikerjakan
- apakah ada TODO/stub kritis yang masih membuat fitur belum usable
- apakah perlu mengusulkan update status di Linear

## 11A. Aturan Verifikasi Manual Oleh User

Untuk repo SIGAP ini, default verifikasi runtime tetap di tangan user kecuali user meminta eksplisit.

- agent tidak boleh otomatis menjalankan `flutter analyze`, `flutter test`, `flutter run`, atau proses build hanya karena selesai mengedit kode
- agent boleh mengusulkan command verifikasi yang relevan, tetapi eksekusinya menunggu instruksi user
- jika agent butuh memastikan API atau struktur kode, utamakan pembacaan kode, dokumentasi resmi, dan reasoning statis sebelum menjalankan command verifikasi
- jika verifikasi belum dijalankan, agent harus menyatakannya secara eksplisit sebagai "belum diverifikasi manual oleh user"

## 12. Default Behavior Untuk Repo Ini

Jika konteks tidak jelas, gunakan default berikut:

- platform utama: Flutter Android-first
- target utama: fitur offline yang benar-benar jalan
- prioritas utama: unblock assistant core flow
- utamakan implementasi nyata dibanding polish visual
- gunakan Linear sebagai alat navigasi kerja, bukan pengganti verifikasi kode

## 13. Contoh Prinsip Kerja Yang Benar

Contoh baik:

- "Issue PRI-51 sebaiknya dikerjakan dulu karena `AssistantScreen` masih mengembalikan placeholder dan `GemmaService` belum terhubung."
- "Linear menyebut Gemma 4 E4B, tetapi file model yang kompatibel dengan `flutter_gemma` masih perlu diverifikasi."
- "UI home sudah ada, jadi issue UI tambahan bukan blocker utama saat ini."

Contoh yang salah:

- "Model sudah siap dipakai" padahal baru ada stub service
- "Format Transformers pasti bisa dipakai di Flutter"
- "Semua issue milestone minggu 1 sudah selesai" hanya karena ada 1 issue done

## 14. Ringkasan Satu Kalimat

Untuk SIGAP, agent yang baik harus berpikir seperti engineer produk yang disiplin: verifikasi dulu, cocokkan dengan repo, gunakan Linear untuk arah kerja, dan jangan pernah menutupi ketidakpastian teknis dengan jawaban yang terdengar yakin.

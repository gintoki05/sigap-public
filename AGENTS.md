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

## 15. Product Context & Vision

*(Konteks produk di bawah ini wajib dipahami oleh agent agar keputusan dan panduan teknis selalu sejalan dengan visi, skenario pengguna nyata, dan target rilis aplikasi).*

**SIGAP: An Offline Emergency Companion for Families on the Move**

Helping families take the first safe action in a medical emergency, even when signal cannot be trusted.

**Track:** Health & Sciences  
**Special Technology Track:** LiteRT  

### The Problem
In Indonesia, emergencies rarely happen in ideal conditions. They happen at home, on the roadside, and during long-distance travel when families are tired, roads are crowded, and connectivity may be unreliable.

This becomes especially visible during mudik, Indonesia’s annual Eid homecoming season. The Ministry of Transportation estimated 146.48 million traveler movements during the 2025 mudik period, showing just how many families are on the road at the same time.

For many travelers, the problem is not only distance. It is uncertainty.

Indonesia still has meaningful connectivity gaps. Based on 2024 BPS data, 3,117 villages/subdistricts were still not covered by cellular signal. Even when internet exists, it cannot always be assumed to be stable or accessible in a stressful, time-sensitive situation.

In a health emergency, that gap matters. People often do not freeze because they do not care, but because they do not know what to do first. The need for basic emergency response knowledge is significant enough that Indonesia’s Ministry of Health provides a dedicated Basic Life Support training curriculum for the general public, explicitly aiming to help ordinary citizens give first aid in cases of illness, injury, or accidents.

Unsafe first-aid myths are also a real risk. Indonesia’s Ministry of Health has explicitly warned against using toothpaste on burns, explaining that it can worsen injury, increase irritation, and raise infection risk. In a real emergency, online information may exist, but search results are not the same as calm, structured, immediate guidance.

A Jakarta emergency-care study also reported a median ambulance response time of 24 minutes, highlighting that in emergencies there can be a meaningful gap between the onset of a problem and professional help arriving.

SIGAP is built for that first critical window: the moment before a family can reliably reach formal help, when what they need most is the next safe action.

### The Solution
SIGAP is an Android offline emergency companion powered by Gemma 4 through `flutter_gemma` and LiteRT. It is designed to help users stay calm and take safer first steps during a health-related emergency, even when internet access is weak or unavailable. Its current product focus is first-step emergency guidance, not diagnosis and not full medical decision-making.

SIGAP is designed around a simple idea:  
*In an emergency, people do not need more information. They need the next safe action.*

Instead of acting like a generic chatbot, SIGAP is designed to turn panic, fragmented input, and uncertain conditions into structured first-step guidance.

In the current product direction, SIGAP centers on:
- offline first-aid guidance
- multimodal reporting through chat, voice, and photo
- urgency-based active guidance
- spoken instructions with text-to-speech
- emergency coordination support through GPS and WhatsApp
- local retrieval for first-aid protocols and myth correction

### Hero Scenario: Mudik Without Signal
The strongest hackathon demo scenario for SIGAP is mudik.

A family is traveling long distance during the Eid homecoming season. While on the road, their child starts vomiting repeatedly and becomes weak. They are in an area with poor signal. They cannot rely on search, messaging, or video tutorials. They need help that works immediately on the phone they already hold.

That is where SIGAP becomes meaningful:
1. The parent opens SIGAP.
2. They describe the condition by voice, text, or photo.
3. SIGAP responds fully offline on-device.
4. It provides safe, structured first-step guidance and highlights red flags.
5. If escalation is needed, the app helps the user prepare to contact help and share location once connectivity is available.

This is not just a dramatic story. It is practical, local, and easy to understand in the Indonesian context.

### Why This Matters in Indonesia
Indonesia is a strong fit for SIGAP because the product is designed around conditions many families already experience:
- long travel distances
- variable signal quality outside major urban centers
- moments of panic where reading articles is unrealistic
- the need for practical and immediate guidance in Bahasa Indonesia

Mudik concentrates all of those realities into one familiar national moment. With 146.48 million projected traveler movements in 2025, the scale alone makes this a meaningful scenario for a health-focused emergency tool.

At the same time, Indonesia already has formal emergency escalation pathways. The Ministry of Health operates PSC 119 as a rapid-response emergency health service. During the 2025 mudik period, the Ministry also activated more than 2,500 health service posts, more than 24,000 reserve health personnel, and 376 PSC 119 units across Indonesia. SIGAP is not intended to replace that system. It is designed to help families take safer first steps before they can reach a health post, contact emergency services, or regain signal.

That is why SIGAP is meaningful in Indonesia: it does not compete with the formal emergency system. It fills the gap before the formal system becomes reachable.

### Why Gemma 4, flutter_gemma, and LiteRT
SIGAP depends on one key technical requirement:  
*the assistant must still work when the network does not.*

That is why the application is built around on-device inference using Gemma 4, `flutter_gemma`, and LiteRT.

- **True on-device operation:** The core assistant runs directly inside the Android app. After setup, the main emergency guidance flow remains useful without internet access. This is not a cloud product with an offline fallback message. It is an offline-first product by architecture.
- **Multimodal input in one mobile experience:** In emergencies, users do not always want to type. SIGAP supports text, voice, and photo input because panic makes it harder to structure information cleanly. Multimodal interaction reduces that burden.
- **Local knowledge retrieval:** SIGAP combines generative guidance with local retrieval. A device-side knowledge base stores first-aid protocols and myth-correction content so the assistant can reinforce safer, more conservative guidance even without network access.
- **Offline-first privacy:** Health-related inputs are sensitive. Keeping inference on-device means users do not need to send their emergency descriptions, voice inputs, or images to the cloud just to receive useful first-step guidance.

### What Makes SIGAP Different
SIGAP is not designed to be a generic medical chatbot. Its differentiators are:
1. **It works when connectivity cannot be trusted:** The value of SIGAP is highest in the exact moment cloud tools become less dependable: when a family is stressed, signal is weak, and time matters.
2. **It accepts messy real-world emergency input:** Users can speak naturally, type short symptom descriptions, or provide a photo instead of having to form a clean search query.
3. **It is action-oriented, not search-oriented:** SIGAP is built to provide safe next steps, not just explanations. Its purpose is to help users move from panic to action.
4. **It supports escalation, not false certainty:** SIGAP’s role is to help bridge the first uncertain minutes until professional care, emergency services, or a health facility can be reached.

### Current Implementation
The current prototype is already centered on first-aid guidance rather than a broad “travel assistant” experience. Based on the current codebase, the following building blocks are already implemented or integrated in the prototype:
- `flutter_gemma` integration for Gemma 4 with LiteRT-LM artifacts
- model selection and download/import flow for local models
- active guidance UI in Flutter
- multimodal pathways for text, voice, and photo input
- urgency states for guidance output
- offline-capable text-to-speech playback in Bahasa Indonesia
- GPS access and WhatsApp deep link for emergency messaging
- local RAG storage using SQLite and vector retrieval fallback

The strongest verified value of the current prototype is this:  
*helping users take the first safe action during a health-related emergency when signal is weak or unavailable.*

### Safety-First Design
SIGAP is not positioned as a doctor replacement.
The assistant is designed to:
- provide conservative first-step guidance
- highlight red flags clearly
- encourage escalation to medical help when risk is high
- avoid overclaiming certainty
- avoid presenting first-step guidance as diagnosis

This matters because Indonesia already has formal emergency pathways such as PSC 119, and the correct role for SIGAP is to act as a bridge until those services can be reached. In product terms, the goal is not diagnosis. The goal is safer action during the first uncertain minutes.

### Product Direction
The broader product identity remains intentionally broad: SIGAP is meant to be relevant for emergencies at home, on the road, and in everyday life. For this hackathon, however, the most compelling and emotionally clear demo context is mudik, because it makes the offline value obvious.

One future extension is a Mudik Pack: an offline contextual layer for travel situations, potentially including emergency contacts, travel-specific first-aid guidance, and important offline references for long-distance journeys. In the current repository, this remains a product direction rather than a completed feature.

### Key Insight
The core insight behind SIGAP is simple:  
*In an emergency, people do not need more information. They need the next safe action.*

By combining Gemma 4, LiteRT, local retrieval, multimodal input, and offline emergency coordination inside one Android experience, SIGAP turns a phone into a practical emergency companion that remains useful even when signal cannot be trusted.

### Conclusion
SIGAP is an offline emergency companion built for real-world uncertainty.

Its identity is broad enough for everyday emergencies, but its strongest demo story is mudik: a family on the road, a child becoming sick, signal disappearing, and a phone that still helps.

That is the promise of SIGAP:  
*ready before help arrives, even when the internet does not.*

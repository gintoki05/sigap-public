# Aturan khusus untuk flutter_gemma (MediaPipe) agar tidak dihapus oleh R8
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-keep class io.flutter.util.** { *; }

-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**

# Mengabaikan semua warning missing classes (khusus untuk R8 LiteRT)
-ignorewarnings

# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep audio_service and related player classes
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.justaudio.** { *; }

# Keep androidx lifecycle classes
-keep class androidx.lifecycle.** { *; }
-keep class * extends androidx.lifecycle.LifecycleObserver { *; }

# Suppress Play Core warnings
-dontwarn com.google.android.play.core.**

# FFmpegKit rules (original and new wrapper versions)
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**

# Keep all FFmpegKit native methods
-keepclasseswithmembernames class * { native <methods>; }

# Keep FFmpegKit Config
-keep class com.arthenica.ffmpegkit.FFmpegKitConfig { *; }
-keep class com.antonkarpenko.ffmpegkit.FFmpegKitConfig { *; }

# Keep ABI Detection
-keep class com.arthenica.ffmpegkit.AbiDetect { *; }
-keep class com.antonkarpenko.ffmpegkit.AbiDetect { *; }

# Keep all FFmpegKit sessions
-keep class com.arthenica.ffmpegkit.*Session { *; }
-keep class com.antonkarpenko.ffmpegkit.*Session { *; }

# Keep FFmpegKit callbacks
-keep class com.arthenica.ffmpegkit.*Callback { *; }
-keep class com.antonkarpenko.ffmpegkit.*Callback { *; }

# Preserve all public classes in ffmpegkit
-keep public class com.arthenica.ffmpegkit.** { *; }
-keep public class com.antonkarpenko.ffmpegkit.** { *; }

# ProGuard rules for TelStorage Android App

# Keep Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Hive adapters and models
-keep class io.hive.** { *; }
-keep class * extends io.hive.HiveObject { *; }
-keep class * implements io.hive.TypeAdapter { *; }
-keep class com.umair.telstorage.core.models.** { *; }

# Keep Dio & OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Flutter Deferred Components / Play Core
-dontwarn com.google.android.play.core.**


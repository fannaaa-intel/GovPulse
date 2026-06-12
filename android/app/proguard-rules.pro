# Google ML Kit — ignore optional language packs we don't bundle
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep ML Kit + Firebase classes that use reflection
-keep class com.google.mlkit.** { *; }
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.** { *; }
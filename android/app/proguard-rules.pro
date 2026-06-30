# ML Kit text recognition: plugin references all script recognizers dynamically.
# App only uses Japanese; others are optional — suppress missing class warnings.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# Keep ML Kit text recognition classes from being stripped
-keep class com.google.mlkit.vision.text.** { *; }

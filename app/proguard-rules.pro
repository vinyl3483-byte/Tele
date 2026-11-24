# Telefam Strong R8 Obfuscation & Security Hardening Rules
-optimizationpasses 5
-allowaccessmodification
-repackageclasses 'tf'
-overloadaggressively
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations
-renamesourcefileattribute T

# Strip verbose debug logging in release builds
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
}

# JNI native bridge contract
-keepclasseswithmembers class com.telefam.company.app.core.TelefamNativeBridge {
    native <methods>;
}

# Room Database generated implementations & entities
-keep class * extends androidx.room.RoomDatabase
-keep class com.telefam.company.app.data.local.** { *; }
-dontwarn androidx.room.paging.**

# Application, ViewModel & Moshi JSON models/adapters
-keep class com.telefam.company.app.TelefamApplication { *; }
-keep class com.telefam.company.app.ui.TelefamViewModel { *; }
-keep class com.telefam.company.app.ui.TelefamViewModel$Factory { *; }
-keepclassmembers class com.telefam.company.app.network.** {
    *;
}
-keep class com.telefam.company.app.network.*JsonAdapter { *; }
-keepclassmembers class * {
    @com.squareup.moshi.Json <fields>;
}

# OkHttp & Credential Manager
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }

# smbj + its dependencies are reflection/ServiceLoader heavy: keep them whole.
-keep class com.hierynomus.** { *; }
-keep class net.engio.mbassy.** { *; }
-keep class org.bouncycastle.** { *; }
-keep class com.rapid7.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn org.slf4j.**
-dontwarn javax.el.**
-dontwarn javax.naming.**
-dontwarn org.ietf.jgss.**
-dontwarn sun.security.**
-dontwarn com.sun.**
-dontwarn org.apache.**
-dontwarn net.engio.mbassy.**

# kotlinx.serialization (@Serializable classes are looked up by generated companions)
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class gduvalsc.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class gduvalsc.**$$serializer { *; }
-keepclassmembers class gduvalsc.** { *** Companion; }

# OkHttp (WebDAV): optional TLS providers and annotations it probes by reflection are not on the classpath.
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn javax.annotation.**
-keep class gduvalsc.pvb.core.ServerConnection { *; }
-keep class gduvalsc.pvb.core.ServerConnection$* { *; }
-keepclassmembers class gduvalsc.pvb.core.** { *** Companion; }

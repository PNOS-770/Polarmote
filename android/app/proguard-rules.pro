# Flutter ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Flutter engine
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep your app's main classes
-keep class com.example.Polarmote.** { *; }

# Google Play Core 相关规则 - 解决 R8 缺失类错误
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Flutter 延迟组件相关规则
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# 保持所有 Flutter 相关的类
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# 保持所有 native 方法
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保持所有枚举
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 保持序列化相关
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

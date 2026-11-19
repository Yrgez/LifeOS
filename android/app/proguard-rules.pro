# Release-сборка сжимается R8. SQLCipher обращается к своим классам из нативного кода —
# без этого правила зашифрованная база в release-сборке не открывается.
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }

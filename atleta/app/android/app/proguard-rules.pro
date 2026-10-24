# Regole di R8 per la build release, che riduce e rinomina il codice Java.

# tor-android: il codice nativo di tor usa campi e metodi di TorService per
# nome, attraverso JNI, e la libreria non porta regole sue. Senza questa
# regola R8 li rinomina e l'app si chiude appena parte Tor
# (NoSuchFieldError: no "J" field "torConfiguration").
-keep class org.torproject.jni.** { *; }

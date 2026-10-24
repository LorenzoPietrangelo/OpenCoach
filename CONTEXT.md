# Open Coach

Programma per coach e app per atleti senza server; le regole del sistema sono in
[specifiche.md](specifiche.md), che ha anche il glossario del dominio (§3). Qui stanno i termini
della distribuzione dei programmi.

## Language

**Pagina dei download**:
La pagina web da cui si scaricano l'installer del programma del coach e l'APK dell'app
dell'atleta, con una sezione per il coach e una per l'atleta. È pubblica ma non pubblicizzata:
la trova solo chi ne riceve il link, che a differenza del link d'invito si può girare a chiunque.
_Avoid_: Sito, sito web, store

**Rilascio**:
Una versione dell'installer e dell'APK, sempre insieme e con lo stesso numero, caricata con la
pagina dei download.
_Avoid_: Pubblicazione, revisione (indicano le schede, §3 delle specifiche)

**Chiave di debug**:
La chiave con cui il PC di sviluppo firma l'APK, creata da Android Studio, con una password
pubblica, conservata nel file `debug.keystore`. Finché la si usa, gli aggiornamenti dell'APK si
possono compilare solo su un PC che ha quel file.
_Avoid_: APK non firmato

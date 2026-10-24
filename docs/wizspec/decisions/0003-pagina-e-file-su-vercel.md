# Pagina dei download e file su Vercel

La pagina dei download e i file di ogni rilascio, installer e APK, stanno su Vercel, piano gratuito
Hobby. Lo script di rilascio (`strumenti/rilascio.ps1`) prepara la cartella della pagina sul PC di
sviluppo. La cartella va poi caricata su una sua repo GitHub, che può restare privata ed è
collegata a Vercel, il quale la pubblica a ogni push. Non serve una repo pubblica: anche il codice
resta nella sua repo privata. L'indirizzo è `<progetto>.vercel.app` e porta il nome del progetto,
non quello dello sviluppatore. Sostituisce la 0001.

## Considered options

- Repo pubblica separata con GitHub Pages e Release (0001): l'indirizzo e i link ai file
  avrebbero mostrato l'account GitHub personale.
- Cloudflare Pages: il limite di 25 MiB per file non accoglie l'APK, che avrebbe richiesto un
  secondo servizio (R2) con un bucket pubblico.
- Caricare la cartella con `vercel deploy` dallo script: lo sviluppatore ha preferito il
  collegamento con una repo GitHub.

## Consequences

- Vercel (piano Hobby) e GitHub accettano file fino a 100 MB, e l'APK universale ne pesa 94. Se li
  supera, si divide l'APK per tipo di processore (arm64 ne pesa circa un terzo). Lo script si
  ferma prima, se un file supera il limite.
- La repo della pagina crescerebbe di circa 115 MB a ogni rilascio. Dato che la pagina offre solo
  l'ultimo rilascio, la sua storia si sostituisce ogni volta con un solo commit.
- Il piano Hobby vale solo per un uso personale non commerciale e ha 100 GB di traffico al mese,
  circa 900 download dell'APK. Un Open Coach a pagamento richiederebbe il piano Pro.
- Gli account Vercel e GitHub sono dello sviluppatore: senza di essi la pagina non si aggiorna.
- Chi scarica non può confrontare i file con il codice, che è privato: la pagina indica
  l'impronta SHA-256 di ogni file.

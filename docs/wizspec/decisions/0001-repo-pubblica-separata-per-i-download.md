---
status: superseded by 0003
---

# Una repo pubblica separata per i download

La repo del codice resta privata, ma installer e APK devono poter essere scaricati da chi riceve il
link, senza account GitHub. Si usa quindi una seconda repo pubblica, solo per la distribuzione: la
pagina dei download sta su GitHub Pages e i file nelle sue Release. Così non servono server né costi
(§1.2), e la scelta più difficile da annullare, rendere pubblico il codice, resta aperta.

## Considered options

- Rendere pubblica la repo del codice, con pagina e Release lì: è la «pagina delle release del
  progetto» del §2, ma pubblicare il codice non si annulla. Resta possibile in futuro, spostando
  pagina e Release.
- Netlify, Cloudflare Pages o Google Drive: un account e un servizio esterno in più, senza
  vantaggi rispetto a GitHub, che il progetto usa già.

## Consequences

- Le Release della repo pubblica contengono solo file compilati: chi li scarica non può verificarli
  confrontandoli con il codice, quindi la pagina deve indicare l'impronta SHA-256 di ogni file.
- La pagina va aggiornata a mano, o da un flusso della CI, a ogni nuova versione.

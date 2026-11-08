# Open Coach — Specifiche v1

Versione 1.0 · 18 ottobre 2026

Questo documento definisce la versione 1 del sistema descritto in «Architettura senza server: onion service del coach». Sostituisce l'architettura precedente basata su relay Nostr e PWA.

## 1. Principi

1. Il programma del coach è l'unico server del sistema e serve solo i propri atleti, tramite un onion service Tor v3 incluso nel programma.
2. Lo sviluppatore non gestisce infrastruttura: niente server, account, telemetria, segnalazione automatica degli errori o controllo degli aggiornamenti. Tutto il traffico di rete dei due programmi passa per Tor.
3. Ogni installazione del programma del coach è indipendente, con chiavi, indirizzo e dati propri. Nessuna funzione dipende dall'esistenza del progetto.
4. L'app dell'atleta funziona offline; la rete serve solo a sincronizzare e a cercare i cibi nel catalogo del coach (§10.3).
5. Ogni tipo di dato ha un solo autore: le schede le scrive il coach, i log l'atleta. Non ci sono conflitti di scrittura da risolvere.
6. La sincronizzazione parte sempre dall'app dell'atleta.

## 2. Componenti

| Componente | Piattaforme | Ruolo |
| --- | --- | --- |
| Programma del coach | Windows 10+, macOS 12+, Linux x86_64 | Server: Tor, onion service, API HTTP, archivio, interfaccia del coach |
| App dell'atleta | Android 8.0+ (API 26), iOS 16+ | Client: Tor incorporato, archivio locale, esecuzione delle schede |
| App del coach (§16) | Android 8.0+ (API 26) | Client del programma del coach: Tor incorporato, nessun archivio, chat e dati degli atleti in lettura |
| Rete Tor | — | Trasporto. Non è un componente del progetto |
| Open Food Facts | — | Database pubblico dei prodotti alimentari. Il catalogo dei cibi del programma del coach ne è una copia ridotta (§10.3). Non è un componente del progetto |

Distribuzione:

- App: Google Play e App Store; F-Droid facoltativo.
- Programma del coach: installer scaricabili dalla pagina delle release del progetto. Su Windows firmato Authenticode; su macOS firmato e notarizzato, compreso l'eseguibile `tor`; su Linux AppImage.

## 3. Glossario

| Termine | Significato |
| --- | --- |
| Coach | Utente del programma desktop. Un'installazione corrisponde a un coach. |
| Atleta | Persona seguita dal coach. Esiste solo nell'archivio del coach, non ha un account. |
| Dispositivo | Telefono dell'atleta abbinato al coach. In v1 un atleta ha al massimo un dispositivo attivo. |
| Telefono del coach | Telefono su cui il coach usa l'app del coach (§16). Non è un dispositivo: non appartiene a un atleta e vede i dati di tutti. Ce n'è al massimo uno attivo. |
| Invito | Autorizzazione monouso e a scadenza per abbinare un dispositivo a un atleta. Si consegna come QR o link. |
| Scheda | Programma di allenamento scritto dal coach per un atleta, composto da sedute. |
| Revisione | Versione pubblicata di una scheda. Ogni ripubblicazione crea una revisione nuova. |
| Seduta | Singolo allenamento previsto dalla scheda (es. «Giorno A»), composto da esercizi. |
| Log | Registrazione di un allenamento eseguito, scritta dall'atleta. |
| Giornata | Diario del cibo di un giorno, scritto dall'atleta: gli alimenti mangiati, divisi per pasto (§8.8). |
| Sync | Scambio avviato dall'app: invia i log in coda e riceve le modifiche alle schede. |
| Cursore | Valore opaco che indica fino a quale modifica l'app è aggiornata. |
| Epoca | Identificativo dello stato dell'archivio del coach. Cambia a ogni ripristino da backup. |

## 4. Chiavi e segreti

| Elemento | Tipo | Generato da | Dove si trova | Durata |
| --- | --- | --- | --- | --- |
| Chiave d'identità del coach | Ed25519 | Programma, al primo avvio | PC del coach, cifrata con il portachiavi del SO | Permanente |
| Indirizzo onion | v3, 56 caratteri | Derivato dalla chiave d'identità | PC del coach e app | Permanente |
| Chiave d'invito | X25519 (client authorization Tor) | Programma, una per invito | Privata: nel QR e sul PC finché l'invito è aperto. Pubblica: tra i client autorizzati del servizio | Fino a conferma, scadenza o annullamento dell'invito |
| Segreto d'invito | 32 byte casuali | Programma | Nel QR e sul PC finché l'invito è aperto, per poter mostrare di nuovo il QR | Come l'invito |
| Chiave del dispositivo | X25519 (client authorization Tor) | App, durante l'abbinamento | Privata: solo sul telefono. Pubblica: tra i client autorizzati del servizio | Fino alla revoca |
| Token del dispositivo | 32 byte casuali | Programma, durante l'abbinamento | Telefono; sul PC solo l'hash SHA-256 | Fino alla revoca |
| Chiave e token del telefono del coach (§16) | Come quelli del dispositivo | App del coach e programma | Come quelli del dispositivo | Fino alla revoca |

Regole:

- La chiave privata del dispositivo non lascia mai il telefono.
- Sul telefono chiave e token sono cifrati con una chiave del Keystore (Android) o salvati nel Keychain (iOS, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Sono esclusi dai backup del sistema operativo e dal trasferimento su un nuovo telefono, che va quindi riabbinato.
- Sul PC del coach la chiave d'identità è cifrata con il portachiavi del SO (DPAPI su Windows, Keychain su macOS, Secret Service su Linux). Se il portachiavi non è disponibile, è salvata in un file leggibile solo dall'utente.
- La chiave d'identità non ruota. Se è compromessa, il coach usa «Reimposta identità»: nuovo indirizzo, tutti i dispositivi revocati, tutti gli atleti da reinvitare.
- Tutte le chiavi e i segreti nel protocollo sono codificati in base32 minuscolo senza padding (32 byte = 52 caratteri).

## 5. Abbinamento

### 5.1 Invito

- Il coach crea l'atleta (basta il nome) e genera un invito. Ogni invito appartiene a un atleta.
- Scadenza predefinita 7 giorni, impostabile da 1 ora a 30 giorni. L'invito è monouso.
- Alla creazione il programma aggiunge la chiave pubblica d'invito ai client autorizzati del servizio.
- Finché l'invito è aperto il coach può mostrare di nuovo il QR o annullarlo. Un nuovo invito per lo stesso atleta annulla quello precedente.
- Consegna: QR mostrato sullo schermo del coach (modo consigliato), oppure link copiabile da inviare con altri mezzi. Il programma avverte che il link va trattato come una password.
- Se l'atleta ha già un dispositivo attivo, il programma avverte che il nuovo abbinamento lo revocherà e che i log non ancora inviati dal vecchio telefono resteranno solo lì: l'atleta deve sincronizzarlo prima.

### 5.2 Formato del QR e del link

```
opencoach://invito?v=1&o=<onion>&i=<id>&s=<segreto>&k=<chiave>
```

| Parametro | Contenuto | Lunghezza |
| --- | --- | --- |
| `v` | Versione del formato, `1` | 1 |
| `o` | Indirizzo onion senza `.onion` | 56 |
| `i` | Id dell'invito, 16 byte casuali | 26 |
| `s` | Segreto d'invito | 52 |
| `k` | Chiave privata X25519 d'invito | 52 |

- Il QR contiene l'URI intero in modalità byte, correzione d'errore M.
- L'app accetta la stessa stringa incollata a mano.
- Con un valore di `v` sconosciuto l'app chiede di aggiornarsi.
- Il nome del coach non è nel QR: l'app lo legge da `GET /v1/info` dopo essersi collegata.

### 5.3 Flusso

1. L'atleta scansiona il QR con l'app o apre il link.
2. L'app genera la coppia di chiavi X25519 del dispositivo.
3. L'app configura Tor con la chiave d'invito per l'indirizzo `o` e chiama `GET /v1/info`. Mostra «Collegarti a <nome del coach>?» e aspetta la conferma dell'atleta.
4. L'app chiama `POST /v1/abbinamento` con id e segreto dell'invito, chiave pubblica del dispositivo e dati del dispositivo.
5. Il programma verifica l'invito, crea il dispositivo, emette il token e revoca l'eventuale dispositivo precedente dell'atleta. Dopo aver inviato la risposta aggiunge la chiave del dispositivo ai client autorizzati e ripubblica il servizio (§9.2). La chiave d'invito resta autorizzata.
6. L'app salva token e chiave, toglie la chiave d'invito dalla configurazione di Tor e riavvia il client Tor, così scarta il descrittore in cache. Poi chiama `POST /v1/abbinamento/conferma`. Se la chiamata fallisce ritenta con attesa crescente per almeno 10 minuti, perché il nuovo descrittore può impiegare qualche minuto a propagarsi; poi riprova a ogni apertura dell'app.
7. Alla conferma il programma chiude l'invito e toglie la chiave d'invito dal servizio. Se la conferma non arriva entro la scadenza dell'invito, il programma toglie comunque la chiave d'invito; il dispositivo resta attivo.
8. L'app esegue la prima sync, completa (§7.3).

Ripetere `POST /v1/abbinamento` con la stessa chiave di dispositivo prima della conferma restituisce un token nuovo e invalida il precedente: copre il caso in cui la risposta si perda, e l'app lo fa da sola quando la risposta non arriva.

### 5.4 Errori durante l'abbinamento

| Situazione | Messaggio all'atleta |
| --- | --- |
| QR non valido | «Questo codice non è un invito di Open Coach.» |
| Invito scaduto, usato o annullato | «Invito non più valido. Chiedi al coach un nuovo QR.» |
| Coach non raggiungibile | «Il PC del coach non è raggiungibile. Deve essere acceso con il programma aperto.» |
| Invito già in uso da un altro telefono | «Questo invito è già stato usato da un altro telefono. Chiedi al coach un nuovo QR.» |

Il caso dell'ultima riga indica anche che il link può essere stato intercettato: il programma lo segnala al coach.

### 5.5 Cambio di telefono

Il coach genera un nuovo invito per lo stesso atleta. Il nuovo dispositivo sostituisce il precedente (§5.3, punto 5) e con la prima sync completa riceve le schede e lo storico dei log presenti sul PC del coach.

## 6. Protocollo

### 6.1 Trasporto

- HTTP/1.1 sopra l'onion service, porta virtuale 80. Niente TLS: cifratura end-to-end e autenticazione del server le fornisce Tor, perché l'indirizzo è la chiave pubblica del coach.
- Il server HTTP ascolta solo su `127.0.0.1`, su una porta casuale scelta all'avvio. Non deve essere raggiungibile da nessun'altra interfaccia.
- Il server rifiuta con 421 le richieste con `Host` diverso da `<onion>.onion` e con 403 quelle con intestazione `Origin`. Così una pagina web aperta sul PC del coach non può chiamare la porta locale.
- La client authorization v3 è sempre attiva: solo chi possiede una chiave autorizzata (invito aperto, dispositivo attivo o telefono del coach, §16) può decifrare il descrittore e raggiungere il servizio.
- L'app si collega via SOCKS5 lasciando la risoluzione del nome a Tor, con gli errori SOCKS estesi attivi (`ExtendedErrors`) per distinguere i guasti (§7.5).

### 6.2 Convenzioni

- Corpi in JSON UTF-8 con `Content-Type: application/json`, chiavi in snake_case.
- Date e ore in ISO 8601 con fuso orario (`2026-10-21T18:30:00+02:00`), date semplici `YYYY-MM-DD`. Id in UUID v4 minuscolo.
- Autenticazione con `Authorization: Bearer <token>` su tutte le chiamate tranne `GET /v1/info` e `POST /v1/abbinamento`. Ogni dato letto o scritto con un token è limitato all'atleta di quel token.
- La versione maggiore del protocollo è nel percorso (`/v1`). Entro la stessa versione si aggiungono solo campi facoltativi, ed entrambe le parti ignorano i campi sconosciuti.
- Limiti: richiesta e risposta fino a 2 MiB (oltre si pagina), un log fino a 64 KiB, una scheda fino a 256 KiB, al massimo 100 log per richiesta.
- Frequenza: al massimo 30 richieste al minuto per dispositivo, 10 tentativi al minuto in totale su `POST /v1/abbinamento`, 10 sync contemporanee.
- Timeout lato app: 90 s per stabilire la connessione, 60 s per ricevere la risposta. Nella lettura dell'invito e nell'abbinamento (§5.3, punti 3 e 4) ogni tentativo dura al massimo 30, poi 45, poi 60 s, e i tentativi si ripetono per circa 2 minuti: una connessione a volte resta appesa, mentre una nuova riesce in pochi secondi.
- Formato degli errori: `{ "errore": "<codice>", "messaggio": "<testo tecnico>" }`. L'app mostra i propri testi in base al codice, non il messaggio.

### 6.3 Endpoint

#### `GET /v1/info`

Senza autenticazione. Risposta 200:

```json
{
  "protocollo": [1],
  "nome_coach": "Marco Bianchi",
  "versione_programma": "1.0.0",
  "versione_app_minima": "1.0.0"
}
```

#### `POST /v1/abbinamento`

Senza token: si autentica con il segreto d'invito.

```json
{
  "invito_id": "…",
  "segreto": "…",
  "chiave_dispositivo": "<X25519 pubblica>",
  "dispositivo": { "nome": "Pixel 8", "piattaforma": "android", "versione_app": "1.0.0" }
}
```

Risposta 200:

```json
{
  "atleta_id": "…",
  "dispositivo_id": "…",
  "token": "…",
  "nome_atleta": "Giulia Rossi",
  "nome_coach": "Marco Bianchi"
}
```

Errori: 410 `invito_non_valido` (inesistente, segreto errato, scaduto, usato o annullato); 409 `invito_in_uso` (invito già usato con un'altra chiave di dispositivo e non ancora confermato).

#### `POST /v1/abbinamento/conferma`

Con token, corpo vuoto. Risposta 204. Idempotente.

#### `POST /v1/sync`

Con token.

```jsonc
{
  "epoca": "…",          // null alla prima sync
  "cursore": "…",        // null = chiedi lo stato completo
  "log": [ /* Log, al massimo 100 */ ],
  "pesi": [ /* Peso (§8.5), al massimo 500; facoltativo */ ],
  "pesi_condivisi": true,  // facoltativo: false = l'atleta non condivide il peso con questo coach
  "giornate": [ /* Giornata (§8.8), al massimo 100; facoltativo */ ],
  "cibo_condiviso": true,  // facoltativo: false = l'atleta non condivide il cibo con questo coach
  "versione_app": "1.0.3"
}
```

Risposta 200:

```jsonc
{
  "epoca": "…",
  "completo": false,
  "log_accettati": [ { "id": "…", "rev": 2 } ],
  "log_rifiutati": [ { "id": "…", "errore": "non_valido" } ],
  "schede": [ /* Scheda */ ],
  "schede_eliminate": [ "…" ],
  "log": [ /* Log, solo se completo */ ],
  "cursore": "…",
  "altro": false,
  "pesi_accettati": [ { "id": "…", "rev": 3 } ],
  "pesi": [ { "id": "…", "rev": 3 } ],  // solo se completo
  "giornate_accettate": [ { "id": "…", "rev": 4 } ],
  "giornate": [ { "id": "…", "rev": 4 } ],  // solo se completo
  "obiettivo_cibo": { "kcal": 2200, "proteine_g": 140 }  // facoltativo, vedi sotto e §8.8
}
```

- Il server tratta prima i log ricevuti, poi calcola le modifiche da restituire.
- La risposta è completa (`completo: true`) se `cursore` è null o se `epoca` è null o diversa da quella attuale. In quel caso `schede` contiene tutte le schede pubblicate e archiviate dell'atleta e `log` tutti i suoi log, compresi gli eliminati nella forma `{ "id", "rev", "eliminato": true }`.
- In una risposta incrementale `schede` contiene solo le schede cambiate dopo il cursore e `log` è vuoto.
- Con `altro: true` l'app ripete la chiamata con il nuovo cursore e senza log, finché `altro` è false.
- Codici d'errore per `log_rifiutati`: `non_valido` (schema), `troppo_grande`, `altro_atleta` (id già usato da un altro atleta).
- I pesi (§8.5) sono un'aggiunta entro la v1. Il programma tratta i pesi ricevuti come i log e li elenca in `pesi_accettati`; un peso non valido o di un altro atleta non compare e l'app lo ritenta. Con `pesi_condivisi: false` il programma cancella tutti i pesi dell'atleta e ignora quelli inviati. Nella risposta completa `pesi` elenca `id` e `rev` di tutti i pesi che il programma ha dell'atleta, comprese le eliminazioni, dopo schede e log.
- Una risposta senza `pesi_accettati` viene da un programma che non conosce i pesi: l'app smette di mandarglieli e lo dice all'atleta, finché una risposta successiva non contiene il campo.
- Anche il cibo (§8.8) è un'aggiunta entro la v1, e segue le regole dei pesi: il programma tratta le giornate ricevute come i log e le elenca in `giornate_accettate`; una giornata non valida, oltre i 64 KiB o di un altro atleta non compare e l'app la ritenta. Con `cibo_condiviso: false` il programma cancella tutte le giornate dell'atleta e ignora quelle inviate. Nella risposta completa `giornate` elenca `id` e `rev` di tutte le giornate che il programma ha dell'atleta, comprese le eliminazioni, dopo la chat. Una risposta senza `giornate_accettate` viene da un programma che non conosce il cibo: l'app smette di mandargli le giornate e lo dice all'atleta, finché una risposta successiva non contiene il campo.
- L'obiettivo del cibo riceve un numero di sequenza come le schede quando il coach lo fissa, lo cambia o lo toglie. Nella risposta incrementale `obiettivo_cibo` c'è solo se è cambiato dopo il cursore, e `null` vuol dire che il coach l'ha tolto; nella completa c'è sempre, `null` se non è fissato. Senza il campo l'app tiene l'obiettivo che ha.
- Anche i questionari (§8.6) sono un'aggiunta entro la v1. La richiesta può contenere `risposte`, al massimo 20. Il programma salva quelle valide e le elenca in `risposte_accettate` (id del questionario); le altre vanno in `risposte_rifiutate` con `sconosciuto` (questionario inesistente o di un altro atleta), `non_valida` o `foto_mancanti` (manca almeno una delle foto indicate). Rimandare risposte già salvate le conferma senza cambiarle.
- Un questionario mandato o annullato riceve un numero di sequenza come le schede: nella risposta incrementale `questionari` contiene quelli mandati dopo il cursore e `questionari_annullati` gli id di quelli annullati; nella completa `questionari` contiene tutti quelli ancora senza risposta, dopo i pesi.
- Anche la chat (§8.7) è un'aggiunta entro la v1. La richiesta può contenere `messaggi` dell'atleta, al massimo 100. Il programma salva quelli validi e li elenca in `messaggi_accettati` (id); gli altri vanno in `messaggi_rifiutati` con `non_valido`, `altro_atleta` (id già usato da un altro atleta) o `video_mancante` (il programma non ha tutte le parti del video, o non corrispondono all'impronta: l'app le ricarica e ritenta). Rimandare un messaggio già salvato lo conferma.
- Un messaggio del coach riceve un numero di sequenza: nella risposta incrementale `messaggi` contiene quelli scritti dal coach dopo il cursore; nella completa tutta la chat, anche i messaggi dell'atleta, dopo i questionari. Nella risposta completa l'app aggiunge i messaggi che non ha e rimette in coda i propri che il programma non ha più.
- Una risposta senza `messaggi_accettati` viene da un programma che non conosce la chat: l'app tiene i messaggi in coda e lo dice all'atleta, finché una risposta successiva non contiene il campo. I video partono solo verso un programma che ha già mandato il campo.

#### `POST /v1/attendi`

Con la chat aperta l'app chiede al coach di avvisarla appena ha qualcosa di nuovo (§7.4). Corpo: `{"epoca": "…", "cursore": "…", "attesa_s": 25}`, con l'epoca e il cursore dell'ultima sync. Risposta: `{"novita": true}` appena una sync porterebbe schede, questionari o messaggi nuovi, o se il cursore non è incrementale o è di un'altra epoca; `{"novita": false}` dopo `attesa_s` secondi, al massimo 25.

- Non cambia niente sul coach: le novità le porta la sync che l'app fa dopo.
- Non conta tra le sync contemporanee. Ce n'è una per dispositivo: quella nuova conclude la precedente. Si concludono tutte senza novità quando il coach ripubblica il servizio (§9.2).
- Un programma precedente alla 1.3.1 risponde 404: l'app sincronizza ogni 15 secondi.

#### `PUT /v1/foto/<id>`

Con token. Una foto di un questionario: corpo `image/jpeg` di al massimo 1,5 MiB, `<id>` è un UUID generato dall'app. Risposta 204. Idempotente: ricaricare la stessa foto non cambia nulla. Errori: 400 se non è un JPEG, 409 se l'id è già di un altro atleta, 413 se è troppo grande. La foto si lega al questionario quando arrivano le risposte che la citano.

#### `PUT /v1/video/<id>/<parte>`

Con token. Una parte del video allegato a un messaggio (§8.7): corpo `application/octet-stream` di al massimo 1 MiB, `<id>` è l'id del video, un UUID generato dall'app, e `<parte>` va da 0 al numero di parti meno uno. Ogni parte tranne l'ultima è lunga esattamente 1 MiB. Risposta 204. Idempotente. Errori: 400 se la parte è vuota, 404 se `<parte>` è oltre il limite di 32 MiB, 413 se è troppo grande. Le parti si ricompongono quando arriva il messaggio che cita il video: se la dimensione e lo SHA-256 corrispondono il video si salva, altrimenti le parti si cancellano e il messaggio si rifiuta con `video_mancante`.

#### `GET /v1/cibo` e `GET /v1/cibo/<codice>`

Con token. La ricerca nel catalogo dei cibi del coach (§10.3): `GET /v1/cibo?q=<testo>` risponde `{ "prodotti": [ … ] }` con i prodotti che contengono tutte le parole di `q`, al massimo 30, dal più pertinente; `GET /v1/cibo/<codice>`, con un codice a barre da 8 a 14 cifre, risponde `{ "prodotto": { … } }`, o `{ "prodotto": null }` se il catalogo non ce l'ha. Un prodotto:

```json
{ "codice": "8001234567890", "nome": "Pasta di semola", "marca": "Pastificio",
  "porzione_g": 80, "per_100g": { "kcal": 353, "proteine": 12, "carboidrati": 72, "grassi": 1.5 } }
```

`marca` e `porzione_g` sono facoltative, e `per_100g` segue le regole del §8.8. Un programma senza catalogo risponde 404 `catalogo_assente`, uno precedente alla 1.6.0 404 `non_trovato`: per l'app è lo stesso. Le chiamate contano nel limite di richieste del dispositivo (§6.2).

#### `DELETE /v1/dispositivo`

Con token. L'atleta si scollega dal coach; il programma revoca il dispositivo. Risposta 204.

### 6.4 Codici di stato

| Stato | Codice | Significato | Comportamento dell'app |
| --- | --- | --- | --- |
| 400 | `richiesta_non_valida` | JSON non valido o non conforme al protocollo | Errore di programmazione, non ritenta |
| 401 | `token_revocato` | Dispositivo revocato o token sconosciuto | Sospende la sync con questo coach; i dati restano consultabili ed esportabili |
| 403 / 404 / 405 / 421 | `origine_vietata`, `non_trovato`, `metodo_non_ammesso`, `host_errato` | Richiesta non conforme | Errore di programmazione, non ritenta |
| 409 / 410 | vedi §6.3 | Abbinamento non possibile | Messaggi del §5.4 |
| 413 | `troppo_grande` | Richiesta oltre i limiti | Divide il lotto di log |
| 426 | `aggiorna_app` | App sotto `versione_app_minima` | Chiede di aggiornare l'app |
| 429 / 503 | `troppe_richieste` / `occupato` | Limite di frequenza o di sync contemporanee | Ritenta dopo `Retry-After` |
| 5xx | `errore_interno` | Errore del programma | Ritenta con attesa crescente |

## 7. Sincronizzazione

### 7.1 Proprietà dei dati

| Dato | Autore | Sull'altro lato |
| --- | --- | --- |
| Schede e revisioni | Coach | Sola lettura sul telefono |
| Log | Atleta | Sola lettura sul PC del coach |
| Pesi | Atleta | Sola lettura sul PC dei coach con cui l'atleta li condivide |
| Giornate del cibo | Atleta | Sola lettura sul PC dei coach con cui l'atleta le condivide |
| Obiettivo del cibo | Coach | Sola lettura sul telefono |
| Questionari | Coach | Sola lettura sul telefono, salvo le risposte |
| Risposte ai questionari e foto | Atleta | Sola lettura sul PC del coach; inviate, non si modificano più |
| Note private del coach sull'atleta | Coach | Non inviate |

### 7.2 Lato programma

- Ogni modifica visibile all'atleta (pubblicazione, nuova revisione, archiviazione o eliminazione di una scheda) riceve un numero di sequenza crescente. Le bozze non arrivano all'atleta.
- Log ricevuti: se l'id non esiste viene salvato; se esiste con `rev` minore viene sostituito; se esiste con `rev` uguale o maggiore viene confermato senza modifiche. Un log eliminato perde il contenuto e conserva solo `id`, `rev` ed `eliminato`.
- Ogni richiesta si tratta in una transazione: i log accettati sono salvati tutti prima di rispondere, oppure nessuno.
- Il programma registra il cursore che ogni dispositivo invia. Una revisione risulta «ricevuta» quando un dispositivo invia un cursore successivo alla sua sequenza, cioè dopo averla salvata.
- L'epoca è un UUID generato all'installazione e rigenerato a ogni ripristino da backup.

### 7.3 Lato app

Una sync con un coach:

1. Avvia Tor, se non è già attivo.
2. Prende dalla coda fino a 100 log, cioè i log con `rev` maggiore dell'ultima `rev` confermata dal coach. Se l'atleta condivide il peso con quel coach, prende anche fino a 500 pesi con `rev` maggiore dell'ultima confermata da lui, escluse le eliminazioni di pesi che il coach non ha mai ricevuto. Allo stesso modo, se gli condivide il cibo, prende fino a 100 giornate.
3. Chiama `POST /v1/sync` con il cursore e l'epoca salvati, e con `pesi_condivisi` e `cibo_condiviso`.
4. Con una risposta incrementale applica in un'unica transazione locale: schede nuove o cambiate, schede eliminate, log confermati (solo se la `rev` locale è ancora quella inviata), obiettivo del cibo, nuovo cursore. I pesi e le giornate confermati si registrano come confermati da quel coach.
5. Se `altro` è true o restano log, pesi o giornate in coda, torna al punto 2.

Con una risposta completa l'app accumula tutte le pagine e le applica insieme solo dopo l'ultima:

- sostituisce l'insieme delle schede con quello ricevuto;
- inserisce i log che non ha, e prende la versione del coach se ha `rev` maggiore;
- rimette in coda i log locali assenti dalla risposta o presenti con `rev` minore. Così, dopo un ripristino del coach da backup, i telefoni reinviano i log arrivati dopo quel backup;
- considera confermati da quel coach esattamente i pesi elencati in `pesi` e le giornate elencate in `giornate`, con la loro `rev`: gli altri tornano in coda per lui;
- sostituisce l'obiettivo del cibo con quello ricevuto;
- salva cursore ed epoca.

Se una sync completa si interrompe, la successiva ricomincia da capo.

Nessun dato va perso se la connessione cade in qualsiasi punto: il programma tratta i log in modo idempotente, e l'app avanza il cursore e svuota la coda solo dopo aver salvato la risposta.

I log rifiutati restano sul telefono, segnalati all'atleta, e non vengono ritentati in automatico.

### 7.4 Quando parte la sync

App in primo piano:

- all'apertura e al ritorno in primo piano;
- subito dopo il salvataggio, la modifica o l'eliminazione di un log;
- con il tasto «Sincronizza ora» o trascinando per aggiornare;
- ogni 10 minuti finché l'app resta aperta;
- mentre l'atleta guarda la chat, appena il coach ha qualcosa di nuovo: c'è sempre un `POST /v1/attendi` in sospeso, che non blocca le sync. Se il programma del coach non lo conosce, ogni 15 secondi.

Se il coach non è raggiungibile, l'app ritenta dopo 30 s, 2 minuti e 5 minuti, poi aspetta la prossima occasione.

App in background:

- Android: lavoro periodico con WorkManager, predefinito ogni 60 minuti (impostabile: disattivato, 15 o 30 minuti, 1, 3 o 6 ore), solo con rete disponibile e batteria non scarica. Una sync iniziata in primo piano prosegue come lavoro accelerato se l'app viene chiusa.
- Android, dopo una conversazione: se l'app si chiude entro 10 minuti dall'ultimo messaggio, partono controlli dopo 1, 3, 5 e 10 minuti, con le stesse condizioni. Un messaggio nuovo ricevuto così li fa ripartire da capo; riaprendo l'app si annullano. Con la sync in background disattivata non ci sono. Android può rimandarli, come ogni lavoro.
- iOS: `BGAppRefreshTask`, senza garanzie su se e quando il sistema lo esegue, e `beginBackgroundTask` per completare una sync in corso quando l'app va in background. Nella pratica su iOS la sync avviene ad app aperta, e l'interfaccia lo dice.
- Quando una sync in background riceve una scheda nuova o una nuova revisione, l'app mostra una notifica locale.

Tor sul telefono è attivo con l'app in primo piano e durante le sync in background, spento negli altri casi. Il suo stato (consenso, guardie) resta salvato tra un avvio e l'altro per ridurre tempi e traffico.

### 7.5 Stato mostrato all'atleta

Per ogni coach sono sempre visibili l'ultima sync riuscita e il numero di log in attesa di invio.

| Situazione | Come si rileva | Messaggio |
| --- | --- | --- |
| Nessuna rete | Sistema operativo | «Sei offline. Gli allenamenti restano salvati sul telefono.» |
| Tor non parte | Bootstrap non completato in 60 s | «Non riesco a collegarmi alla rete Tor da questa connessione. Prova con un'altra rete, per esempio i dati mobili.» |
| PC del coach spento o programma chiuso | Errori SOCKS `F0`, `F2`, `F3`, `F7`, timeout | «Il PC del coach non è raggiungibile. I tuoi allenamenti partiranno appena tornerà acceso.» |
| Chiave non più autorizzata | Errori SOCKS `F4` o `F5` in 3 sync consecutive | «Il collegamento con il coach non è più valido. Chiedi un nuovo invito.» |
| Dispositivo revocato | HTTP 401 | «Il coach ha chiuso il collegamento.» |
| App troppo vecchia | HTTP 426 | «Aggiorna l'app per continuare a sincronizzare.» |

## 8. Modello dati

### 8.1 Scheda

```jsonc
{
  "id": "…",
  "revisione": 3,
  "stato": "pubblicata",                 // "pubblicata" | "archiviata"
  "titolo": "Forza – blocco 2",
  "note": "…",
  "valida_dal": "2026-10-20",             // facoltativo: il programma non lo scrive più
  "valida_al": "2026-11-16",             // facoltativo: il programma non lo scrive più
  "pubblicata_il": "2026-10-18T21:00:00+02:00",
  "sedute": [
    {
      "id": "…",
      "nome": "Giorno A",
      "note": "…",
      "esercizi": [
        {
          "id": "…",
          "nome": "Squat",
          "note": "Pausa di 1 s in buca",
          "video": "https://www.youtube.com/watch?v=…",   // facoltativo
          "prescrizione": [
            { "serie": 4, "ripetizioni": "6-8", "carico": "75% 1RM", "recupero_s": 150, "rir": "1-2" }
          ]
        }
      ]
    }
  ]
}
```

- `revisione` cresce a ogni ripubblicazione. L'app mostra sempre l'ultima ricevuta.
- `ripetizioni` e `carico` sono testo libero («8», «6-8», «30 s», «RPE 8», «75% 1RM»), come `rir`, le ripetizioni da lasciare in riserva («2», «1-2»). Tutti i campi della prescrizione sono facoltativi.
- `video` è il link a un video che mostra l'esercizio: solo `https`, senza credenziali, al massimo 500 caratteri. Il programma lo prende dalla libreria degli esercizi alla pubblicazione (§9.3). È un campo aggiunto entro la v1: un'app che non lo conosce lo ignora (§6.2).
- Gli id di sedute ed esercizi restano stabili tra le revisioni, così i log restano collegati.
- L'ordine degli array è l'ordine di visualizzazione.
- Le schede archiviate restano sul telefono in sola lettura, nella sezione «Archivio».

### 8.2 Log

```jsonc
{
  "id": "…",                             // generato dall'app
  "rev": 1,                              // cresce a ogni modifica sul telefono
  "eliminato": false,
  "scheda_id": "…",                      // null per un allenamento libero
  "scheda_revisione": 3,
  "seduta_id": "…",
  "eseguito_il": "2026-10-21T18:30:00+02:00",
  "durata_min": 65,
  "rpe": 8,                              // sforzo percepito della seduta, 1–10
  "note": "…",
  "esercizi": [
    {
      "esercizio_id": "…",               // null se aggiunto dall'atleta
      "nome": "Squat",
      "note": "",
      "serie": [
        { "ripetizioni": 8, "carico_kg": 80, "durata_s": null, "rpe": 7.5, "completata": true }
      ]
    }
  ],
  "modificato_il": "2026-10-21T19:40:00+02:00"
}
```

- Il log copia il nome degli esercizi, così resta leggibile anche se la scheda cambia o viene eliminata.
- Per ogni serie è obbligatorio solo `completata`. `rpe` va da 0 a 10 a passi di 0,5.
- Dalla versione 1.3.0 l'app non chiede più `rpe` (né della seduta né delle serie) e `durata_min`: restano nel protocollo, facoltativi, per i log che li hanno già e per le app precedenti. Il programma del coach li mostra quando ci sono.
- Eliminare un log significa inviarlo con `eliminato: true` e `rev` incrementata.
- Un log appartiene a un solo coach. Per un allenamento libero l'atleta sceglie il coach se ne ha più di uno.

### 8.3 Archivio del programma del coach

SQLite in modalità WAL nella cartella dati dell'utente (`%APPDATA%\OpenCoach`, `~/Library/Application Support/OpenCoach`, `~/.local/share/opencoach`).

| Tabella | Contenuto |
| --- | --- |
| `impostazioni` | Nome del coach, epoca, opzioni |
| `identita` | Chiave Ed25519 cifrata |
| `atleti` | Id, nome, note private, stato (attivo, archiviato), data di creazione |
| `inviti` | Id, atleta, segreto e chiavi X25519 d'invito, scadenza, stato (aperto, in abbinamento, usato, scaduto, annullato) |
| `dispositivi` | Id, atleta, chiave X25519 pubblica, hash del token, nome, piattaforma, versione app, data di abbinamento, ultimo contatto, ultimo cursore, stato (attivo, revocato) |
| `schede` | Id, atleta, bozza corrente, stato (bozza, pubblicata, archiviata, eliminata), ultima revisione, sequenza |
| `revisioni` | Contenuto di ogni revisione pubblicata, per mostrare la prescrizione a cui si riferisce un log |
| `log` | Id, atleta, dispositivo, `rev`, contenuto, data di ricezione |
| `libreria` | Id, nome, nome normalizzato (unico), note, link al video |
| `pesi` | Id, atleta, `rev`, eliminato, giorno, kg, data di ricezione |
| `giornate` | Id, atleta, `rev`, eliminato, giorno, contenuto, data di ricezione |
| `obiettivi_cibo` | Atleta, obiettivo (vuoto se il coach l'ha tolto), data, sequenza |
| `questionari` | Modelli scritti dal coach: id, contenuto, date |
| `questionari_inviati` | Id, atleta, modello, contenuto al momento dell'invio, data d'invio, sequenza, stato (inviato, risposto, annullato), risposte, data di ricezione, letto |
| `foto` | Id, atleta, questionario, JPEG, data di ricezione. Stanno nell'archivio, quindi anche nel backup cifrato |

Segreto e chiave privata d'invito si cancellano quando l'invito si chiude.

### 8.4 Archivio dell'app

SQLite nello spazio privato dell'app. Su iOS i file usano la classe di protezione `CompleteUntilFirstUserAuthentication`, così la sync in background può leggerli.

Per ogni coach: indirizzo, nome, id dell'atleta e del dispositivo, cursore, epoca, data dell'ultima sync, se l'atleta gli condivide il peso e se il suo programma lo riceve; le sue schede; i log, ciascuno con la `rev` locale e l'ultima `rev` confermata; per ogni peso, l'ultima `rev` che ha confermato. I pesi stanno una volta sola, fuori dai coach. Allo stesso modo: se l'atleta gli condivide il cibo e se il suo programma lo riceve, il suo obiettivo del cibo, per ogni giornata l'ultima `rev` che ha confermato; le giornate e i cibi già usati stanno una volta sola, fuori dai coach. Chiavi e token sono conservati come descritto al §4.

### 8.5 Peso

```jsonc
{
  "id": "…",                             // generato dall'app, uno per giorno
  "rev": 2,
  "eliminato": false,
  "giorno": "2026-10-27",
  "kg": 72.4,                            // da 20 a 400
  "modificato_il": "2026-10-27T07:30:00+01:00"
}
```

- Un peso per giorno. Correggerlo o eliminarlo incrementa `rev`; il giorno tiene lo stesso `id` anche dopo un'eliminazione. Un peso eliminato si invia come `{ "id", "rev", "eliminato": true }`.
- Il peso è dell'atleta, non di un coach. Per ogni coach l'atleta sceglie se condividerlo: è condiviso per default. Smettendo, alla sync successiva quel coach cancella tutti i pesi dell'atleta; ricominciando, li riceve di nuovo tutti.
- L'app non accetta pesi fuori intervallo o per un giorno futuro.

### 8.6 Questionario

Come lo riceve l'app:

```jsonc
{
  "id": "…",
  "inviato_il": "2026-10-27T10:00:00+01:00",
  "titolo": "Check mensile",
  "descrizione": "…",                    // facoltativa
  "domande": [
    { "id": "…", "tipo": "scelta_singola", "testo": "Quanti giorni a settimana?", "obbligatoria": true,
      "opzioni": ["2 giorni", "3 giorni", "4 giorni"], "altro": true },
    { "id": "…", "tipo": "numero", "testo": "Quanto pesi?", "obbligatoria": true,
      "unita": "kg", "peso_corporeo": true }
  ],
  "foto": { "numero": 5, "istruzioni": "Corpo intero, non allo specchio" }   // facoltativo
}
```

- Tipi di domanda: `testo_breve` (fino a 500 caratteri), `testo_lungo` (fino a 5000), `numero` (con `unita` facoltativa), `scelta_singola` e `scelta_multipla` (con `opzioni` e, se `altro` è true, una risposta scritta), `scala` (intero da 1 a 10). Una domanda `numero` con `peso_corporeo` si precompila con l'ultimo peso registrato dall'atleta.
- Al massimo 100 domande, 50 opzioni per domanda e 10 foto. Un questionario ha almeno una domanda o una richiesta di foto.
- Il contenuto si copia all'invio: cambiare il modello dopo non cambia quello che l'atleta ha ricevuto.

Le risposte, come le manda l'app:

```jsonc
{
  "questionario_id": "…",
  "inviata_il": "2026-10-27T18:00:00+01:00",
  "risposte": [
    { "domanda_id": "…", "valore": { "altro": "Giorni alterni" } },
    { "domanda_id": "…", "valore": 72.4 }
  ],
  "foto": [ "…", "…" ]                   // id delle foto già caricate, quante ne chiede il coach
}
```

- Il valore dipende dal tipo: un testo, un numero, `{ "scelta": "…" }` o `{ "altro": "…" }` per la scelta singola, `{ "scelte": [ … ], "altro": "…" }` per la multipla. Le domande senza risposta non compaiono; quelle obbligatorie devono comparire.
- L'atleta compila anche in più volte: le risposte si salvano sul telefono man mano. Inviate, non si modificano più.
- Le foto si scattano nell'app, e non finiscono nella galleria, oppure si scelgono dalla galleria. Prima di allegarle l'app le ricomprime in JPEG con il lato corto di al massimo 1600 pixel e senza dati EXIF: niente posizione GPS né modello del telefono. Ogni foto si carica con `PUT /v1/foto/<id>` prima delle risposte.
- Il coach può annullare un questionario senza risposta: sparisce dal telefono se l'atleta non l'ha ancora inviato; se l'ha inviato, le risposte arrivano lo stesso.

### 8.7 Messaggio

La chat tra coach e atleta. Un messaggio, come lo scambiano app e programma:

```jsonc
{
  "id": "…",                            // UUID di chi lo scrive
  "autore": "atleta",                   // oppure "coach"
  "testo": "Ultima serie, mi sembra di cedere",
  "inviato_il": "2026-10-21T19:00:00+02:00",
  "video": {                            // facoltativo, solo dall'atleta
    "id": "…",
    "dimensione": 7340032,              // byte, al massimo 32 MiB
    "parti": 7,                         // dimensione / 1 MiB, arrotondato in su
    "sha256": "…",                      // 64 cifre esadecimali
    "durata_s": 42                      // da 1 a 90
  },
  "riferimento": {                      // facoltativo: la serie del video
    "log_id": "…",                      // facoltativo
    "esercizio": "Squat",
    "serie": 4
  }
}
```

- Il testo ha al massimo 4000 caratteri; può essere vuoto solo se c'è un video.
- I messaggi non si modificano. L'atleta può ritirare un proprio messaggio finché non è arrivato al coach. Il coach li legge segnati come nuovi, con una notifica sul desktop.
- Il video di una serie si allega mentre si registra l'allenamento: l'atleta lo gira con la fotocamera o lo sceglie dalla galleria, al massimo di 60 secondi, e parte con il log come messaggio con il riferimento alla serie. L'app lo ricomprime in H.264 a 480p sul lato corto, 30 fotogrammi al secondo, senza audio, circa 1 Mbit/s: un minuto pesa sui 7–8 MB. Prima di calcolarne l'impronta toglie i metadati che possono dire dove e con che telefono è stato girato (le scatole MP4 `udta`, `meta` e `uuid`, compresa la posizione `©xyz`) e lo spazio vuoto che il muxer lascia nel file (le scatole `free` del primo livello, spostando gli offset dei campioni).
- Il video si carica a parti da 1 MiB con `PUT /v1/video/<id>/<parte>` prima del messaggio; se la sync si interrompe, la successiva riprende dalla prima parte mancante. Se il programma rifiuta il messaggio con `video_mancante`, l'app ricarica tutte le parti, fino a tre volte; poi il messaggio resta non inviato e l'atleta può ritentare.
- Sul PC i video stanno in file nella cartella dati, una sottocartella per atleta, e non entrano nel backup (§9.4); il coach li guarda nel programma, che li riproduce con Media Foundation di Windows, e può cancellarli, lasciando il messaggio. Sul telefono stanno nello spazio privato dell'app, esclusi dai backup del telefono.
- Come il resto dei dati, messaggi e video passano solo dal servizio onion (§11.1): nessun server li vede.

### 8.8 Cibo

Una giornata, come la manda l'app:

```jsonc
{
  "id": "…",                             // generato dall'app, uno per giorno
  "rev": 4,
  "eliminato": false,
  "giorno": "2026-11-07",
  "voci": [
    {
      "id": "…",                         // generato dall'app
      "pasto": "colazione",              // "colazione" | "pranzo" | "cena" | "spuntini"
      "nome": "Fette biscottate integrali",
      "marca": "…",                      // facoltativa
      "codice": "8001234567890",         // facoltativo: codice a barre, da 8 a 14 cifre
      "fonte": "open_food_facts",        // oppure "atleta"
      "grammi": 24,                      // da 0,1 a 5000
      "per_100g": { "kcal": 395, "proteine": 13, "carboidrati": 68, "grassi": 5.6 }
    }
  ],
  "modificato_il": "2026-11-07T08:10:00+01:00"
}
```

- Una giornata per giorno, con le regole del peso (§8.5): correggerla incrementa `rev`, il giorno tiene lo stesso `id` anche dopo un'eliminazione, e una giornata eliminata si invia come `{ "id", "rev", "eliminato": true }`. Una giornata senza voci si elimina.
- Ogni voce copia nome e valori dell'alimento, come il log copia i nomi degli esercizi: la giornata resta giusta anche se il prodotto cambia nel catalogo o l'atleta corregge un alimento.
- In `per_100g` è obbligatorio solo `kcal`, da 0 a 900; `proteine`, `carboidrati` e `grassi` sono grammi da 0 a 100, e mancano quando non si conoscono. Per i liquidi 100 g valgono 100 ml, come in Open Food Facts. I totali non si inviano: li calcolano app e programma.
- Al massimo 200 voci per giornata. Il nome ha al massimo 200 caratteri, la marca 100.
- I pasti sono i quattro dell'elenco, sempre gli stessi.
- `fonte` dice da dove vengono i valori: `open_food_facts` se l'atleta ha aggiunto un prodotto del catalogo del coach (§10.3), `atleta` se l'ha scritto lui.
- Il cibo è dell'atleta, non di un coach. Per ogni coach l'atleta sceglie se condividerlo: è condiviso per default. Smettendo, alla sync successiva quel coach cancella tutte le giornate dell'atleta; ricominciando, le riceve di nuovo tutte.
- L'app non accetta giornate per un giorno futuro.

Per i prodotti che il catalogo non ha e per i piatti fatti in casa l'atleta scrive l'alimento a mano: nome, eventualmente la marca, e i valori per 100 g come sopra. Entra nella giornata con `fonte: "atleta"`.

Ogni alimento che l'atleta aggiunge resta sul telefono tra i cibi già usati, con l'ultima porzione: nome, marca, codice, fonte e valori per 100 g, uno per codice a barre o, senza codice, per nome e marca. Si ritrova senza chiedere niente al coach. Togliere una voce dal diario non lo toglie da lì. I cibi già usati non si inviano al coach.

L'obiettivo del cibo lo fissa il coach per l'atleta: `{ "kcal": 2200, "proteine_g": 140, "carboidrati_g": 250, "grassi_g": 70 }`. `kcal` è obbligatorio, da 500 a 8000; gli altri sono facoltativi, da 0 a 1000. È un obiettivo indicativo, non una dieta: il programma non scrive piani alimentari.

## 9. Programma del coach

### 9.1 Avvio e presenza

- Al primo avvio chiede il nome da mostrare agli atleti, genera l'identità, propone l'avvio automatico (attivo per default) e la configurazione del backup.
- Si avvia con la sessione utente, ridotto nell'area di notifica (Windows), nella barra dei menu (macOS) o nel tray (Linux; se manca, resta una finestra).
- Chiudere la finestra lo riduce nell'area di notifica. Si esce solo con «Esci», che avverte che gli atleti non potranno sincronizzare.
- Una sola istanza per utente; un secondo avvio porta in primo piano la finestra esistente.
- Opzione «Impedisci la sospensione del PC mentre il programma è attivo», disattivata per default.
- L'icona mostra lo stato: «Avvio di Tor (n%)», «Raggiungibile», «Non raggiungibile» con il motivo. «Raggiungibile» significa che Tor ha completato il bootstrap e ha caricato almeno un descrittore del servizio (evento `HS_DESC UPLOADED`).
- Dopo la ripresa dalla sospensione o un cambio di rete il servizio torna raggiungibile entro 2 minuti, senza intervento del coach.

### 9.2 Gestione di Tor

- Il programma include l'eseguibile `tor` (ramo stabile, almeno 0.4.8) e lo avvia come processo figlio, con una `DataDirectory` propria, porta di controllo con autenticazione a cookie e `SocksPort 0`.
- Un'impostazione avanzata permette di indicare un eseguibile `tor` esterno, purché di versione supportata.
- Il servizio si crea dalla porta di controllo con `ADD_ONION`, passando la chiave d'identità, `Flags=V3Auth` e un `ClientAuthV3` per ogni chiave autorizzata. La chiave resta nell'archivio del programma e non finisce nei file di Tor.
- Senza telefoni né inviti aperti il servizio non viene pubblicato, perché nessuno potrebbe raggiungerlo.
- Ogni cambiamento delle chiavi autorizzate ricrea il servizio (`DEL_ONION` e poi `ADD_ONION`). I cambiamenti ravvicinati si raggruppano in un'unica ricreazione dopo 5 s, che aspetta la fine delle richieste in corso (al massimo 30 s), perché ricreare il servizio chiude i circuiti aperti.
- Se Tor termina in modo inatteso il programma lo riavvia con attesa crescente fino a 1 minuto e lo segnala nell'icona.
- Se Tor segnala che la sua versione è obsoleta o pericolosa (`STATUS_GENERAL` con `DANGEROUS_VERSION`), il programma invita il coach ad aggiornare. È l'unico avviso di aggiornamento: il programma non contatta altri server.

### 9.3 Funzioni

Atleti:

- creare, modificare, archiviare ed eliminare. Eliminare revoca il dispositivo e cancella tutti i dati dell'atleta, dopo conferma;
- la pagina di un atleta nuovo mostra solo l'invito, con il QR e il link. Appena il telefono si collega lascia il posto alle altre sezioni. Un atleta che ha già avuto un telefono o ha già dei dati continua a vederli anche se il telefono manca, con il pulsante per un nuovo invito;
- dal menu dell'atleta, creare un invito, che annulla quello ancora aperto;
- vedere nell'elenco degli atleti stato, dispositivo e ultimo contatto;
- dal menu dell'atleta, scollegare il telefono: il token smette di valere subito e il servizio viene ripubblicato senza la sua chiave;
- esportare i dati di un atleta in JSON (anagrafica, schede con le revisioni, allenamenti) e in CSV (una riga per serie, nel formato che Excel in italiano apre direttamente). Le note private entrano nell'esportazione solo se il coach lo chiede, perché il file può finire all'atleta.

Schede:

- creare, modificare e duplicare, anche per un altro atleta;
- pubblicare: crea una revisione che l'atleta riceve alla prossima sync. L'atleta ha una sola scheda attiva: quella che aveva passa nell'archivio, per lui e per il coach, e lo stesso vale riportando tra le attive una scheda archiviata. Una bozza non cambia niente finché non è pubblicata. Le modifiche successive restano in bozza fino alla ripubblicazione;
- archiviare ed eliminare;
- vedere per ogni revisione se l'atleta l'ha ricevuta e quando.

Libreria degli esercizi:

- creare, modificare ed eliminare esercizi con nome (unico, senza distinguere maiuscole e spazi ai lati), note e link a un video;
- nell'editor, scrivendo il nome di un esercizio, il programma propone quelli della libreria; sceglierne uno copia nella scheda il nome e, se la scheda non ne ha, le note;
- le schede seguono la libreria per nome: alla pubblicazione ogni esercizio prende il video dell'esercizio con lo stesso nome, o nessun video. La bozza non contiene il video;
- quando la libreria cambia, le schede il cui video cambierebbe risultano con modifiche non pubblicate. Il programma propone di aggiornare i video delle schede pubblicate: crea una revisione dall'ultima pubblicata con i video nuovi, senza le modifiche ancora in bozza. Le schede archiviate restano come sono.

Questionari (§8.6):

- creare, modificare, duplicare ed eliminare modelli: titolo, descrizione, domande di ogni tipo, eventuale richiesta di foto con le istruzioni. Eliminare un modello non tocca i questionari già mandati;
- dalla chat con l'atleta, con l'icona accanto al messaggio, mandare un modello: un check mensile è un questionario rimandato ogni volta dal coach. Annullare un questionario senza risposta, che resta nella chat con il suo stato. Non c'è una sezione a parte: dalla stessa icona si scrivono, modificano, duplicano ed eliminano i modelli;
- leggere le risposte con le foto, segnate come nuove finché non si aprono, con una notifica sul desktop quando arrivano;
- nell'editor delle schede, un pannello accanto mostra le risposte dell'atleta, dalla più recente.

Storico:

- per ogni atleta, grafici invece dell'elenco dei log, per la scheda che sceglie il coach (all'inizio quella attiva), per gli allenamenti liberi o per tutte: gli allenamenti a settimana nelle ultime 12 settimane e i progressi di un esercizio a scelta;
- i progressi seguono il massimale stimato più alto di ogni allenamento, con la formula di Epley: 1RM = carico × (1 + (ripetizioni + RIR) / 30). Il RIR è quello che il coach ha previsto nella revisione seguita dall'atleta («1-2» vale 1,5), o quello che si ricava dall'RPE nei log vecchi che lo hanno; senza RIR la serie vale come a cedimento. Senza ripetizioni si segue il carico, senza carichi la durata, senza durate le ripetizioni;
- contano solo le serie fatte, e un allenamento senza serie fatte non conta. Lo stesso esercizio si riconosce dal nome;
- i log sono in sola lettura e restano interi nelle esportazioni, note comprese.

Peso:

- se l'atleta lo condivide, nella sua pagina: l'ultimo peso, la media degli ultimi 7 giorni e la differenza con i 7 giorni prima, il grafico con i pesi di ogni giorno e la media mobile di 7 giorni, l'elenco;
- i pesi sono in sola lettura ed entrano nell'esportazione JSON.

Cibo (§8.8):

- fissare, cambiare o togliere l'obiettivo dell'atleta: calorie e, se il coach vuole, proteine, carboidrati e grassi. L'atleta lo riceve alla sync successiva;
- se l'atleta lo condivide, nella sua pagina: la media di calorie e macronutrienti degli ultimi 7 giorni registrati, il grafico delle calorie di ogni giorno delle ultime 4 settimane con la linea dell'obiettivo, e l'elenco dei giorni con i totali; aprendo un giorno, i pasti con le voci, i grammi e la fonte dei valori. I giorni senza giornata restano vuoti e non contano nelle medie;
- le giornate sono in sola lettura ed entrano nell'esportazione JSON. Arrivano senza notifica: l'atleta le corregge spesso durante il giorno;
- il catalogo dei cibi (§10.3) arriva con l'installer, accanto all'eseguibile; il programma lo apre all'avvio e risponde con quello alle ricerche degli atleti. Il registro dice quanti prodotti ha e quando è stato generato.

Chat (§8.7):

- nella pagina dell'atleta, la conversazione con i messaggi nuovi segnati sulla scheda e nell'elenco degli atleti; scrivere un messaggio, che l'atleta riceve alla sua sync successiva;
- i video delle serie con l'esercizio e il numero della serie, da guardare nel programma, anche al rallentatore (0,25× e 0,5×) e in ripetizione continua, da aprire con un altro programma o da cancellare per fare spazio.

Notifiche desktop, disattivabili: log ricevuto, abbinamento completato, questionario risposto, messaggio o video ricevuto, invito usato da un secondo telefono.

### 9.4 Backup e ripristino

- Il backup è un file unico, cifrato con una passphrase scelta dal coach (Argon2id e XChaCha20-Poly1305), che contiene identità, archivio e impostazioni. I video della chat (§8.7) restano fuori: un ripristino porta i messaggi, non i video.
- Backup automatico in una cartella scelta dal coach, predefinito ogni settimana, conservando gli ultimi 5. La chiave derivata dalla passphrase resta nel portachiavi del SO per poterlo fare senza chiederla. Backup manuale in ogni momento.
- Se l'ultimo backup ha più di 30 giorni, il programma lo ricorda.
- Il ripristino, sullo stesso PC o su un altro, conserva l'indirizzo onion: gli atleti non devono riabbinarsi. Genera una nuova epoca, così i telefoni reinviano i log arrivati dopo il backup (§7.3).
- Il programma avverte che due installazioni con la stessa identità non devono mai essere attive insieme e, dopo un ripristino su un nuovo PC, chiede di disinstallare o reimpostare quella vecchia.

## 10. App dell'atleta

### 10.1 Tor

- Client Tor incorporato, con supporto per onion service v3, client authorization ed errori SOCKS estesi o un'informazione equivalente. Candidati: `tor` tramite tor-android e Tor.framework, oppure Arti se copre gli stessi requisiti.
- Un'unica istanza di Tor per tutti i coach collegati, con una chiave di client authorization per ciascuno.
- Tor ascolta solo su loopback e lo usa solo l'app.

### 10.2 Funzioni

- L'atleta ha un solo coach alla volta. Con il coach l'app si apre sulle sezioni Allenamento, Chat, Cibo e Peso, e il resto sta nelle impostazioni. Il QR o il link di un altro coach, dopo conferma, collega il telefono al nuovo e solo dopo lo scollega dal precedente, così un coach irraggiungibile non lo lascia senza nessuno. Chi aveva più coach da una versione precedente sceglie all'apertura quale tenere. Di un coach precedente allenamenti e schede restano consultabili nelle impostazioni.
- Primo avvio, e dopo essersi scollegati: «Scansiona il QR del tuo coach», oppure incolla il codice. Nessun account, nessuna registrazione.
- Allenamento: la scheda attiva; lo storico e l'archivio delle schede, due voci chiuse che si aprono con un tocco. Dettaglio delle sedute, scelta della seduta da eseguire, avviso quando arriva una nuova revisione.
- Esecuzione: per ogni esercizio serie, ripetizioni, recupero e RIR si leggono sulla stessa riga. L'atleta scrive ripetizioni e carico effettivi (per gli esercizi a tempo, la durata della serie): una serie con almeno un valore conta come fatta, una vuota no, senza altro da segnare. Lasciando una serie compilata parte il timer di recupero previsto dal coach, che si può avviare anche a mano. Scrive anche le note. Non si chiedono né lo sforzo percepito né la durata dell'allenamento. Può aggiungere esercizi non previsti o registrare un allenamento libero. Al salvataggio il log entra in coda e parte una sync.
- L'ultima volta: per ogni serie i campi vuoti mostrano in grigio ripetizioni, carico e durata della stessa serie nell'allenamento più recente con l'esercizio (stesso id della scheda o stesso nome, con qualsiasi coach; contano solo le serie fatte). Senza un'ultima volta, mostrano in grigio la prescrizione. I valori in grigio non contano finché l'atleta non li scrive.
- Video: aprendo un esercizio con `video`, l'app mostra «Guarda il video». Un video di YouTube si guarda nell'app (`youtube-nocookie.com`), gli altri link si aprono in un'altra app. Il player si carica solo al tocco e va in pausa quando l'esercizio si chiude. Il video non passa da Tor (§11.1).
- Allenamenti fatti: i propri log, modificabili ed eliminabili. Ogni modifica incrementa `rev` e rimette il log in coda.
- Stato della sync come al §7.5, con il tasto «Sincronizza ora».
- Questionari (§8.6): nella chat, dov'è il momento in cui sono arrivati; quelli da compilare restano anche fissi in cima, e la sezione Chat li conta. Una sync in background che ne riceve di nuovi li annuncia con una notifica.
- Peso (§8.5): il peso di oggi o di un altro giorno, la media degli ultimi 7 giorni, il grafico, l'elenco con correzione ed eliminazione, e l'interruttore «condividi» con il coach. Se il suo programma non riceve i pesi, l'app lo dice accanto al nome.
- Cibo (§8.8), una sezione a sé, separata dal peso: il diario di oggi, con i giorni precedenti scorrendo la data, i quattro pasti con le loro voci e, in cima, calorie e macronutrienti del giorno, con l'obiettivo del coach se c'è. Da ogni pasto si aggiunge un alimento: tra i cibi già usati (§8.8), che compaiono subito mentre si scrive; dal catalogo del coach, per nome premendo invio o con il codice a barre (§10.3); oppure scrivendolo a mano. Poi si sceglie la porzione: grammi, o la porzione della confezione quando il catalogo la indica, con i valori ricalcolati prima di aggiungerla. Toccando una voce se ne cambiano i grammi o la si toglie. In fondo, l'interruttore «condividi» con il coach; se il suo programma non riceve il cibo, l'app lo dice accanto al nome. Cibi già usati, alimenti scritti a mano e diario funzionano anche offline e con il PC del coach spento.
- Chat (§8.7): la sezione conta i messaggi nuovi, che diventano letti quando l'atleta la guarda. Mentre la guarda i messaggi arrivano subito (§7.4); una sync in background che riceve messaggi li annuncia con una notifica. Nell'esecuzione, accanto a ogni serie, la videocamera allega il video della serie, che parte al salvataggio.
- Impostazioni: il coach e quelli precedenti (nome, indirizzo, ultima sync); cambiare coach; scollegarsi, che chiama `DELETE /v1/dispositivo` se il coach è raggiungibile e poi, dopo conferma, cancella i dati locali di quel coach; frequenza della sync in background (Android); esportazione dei propri dati in JSON.
- Schede e log restano separati per coach.
- Dopo una revoca le schede e i log di quel coach restano consultabili ed esportabili, ma non si sincronizzano più.
- L'esportazione JSON comprende anche le giornate.

### 10.3 Catalogo dei cibi

I prodotti si cercano nel catalogo dei cibi che il programma del coach tiene sul PC: una copia ridotta di Open Food Facts con i prodotti venduti in Italia. Né l'app né il programma chiamano Open Food Facts mentre funzionano.

- **Che cos'è:** un file SQLite in sola lettura, `cibo/catalogo_italia.sqlite` accanto all'eseguibile del programma, che arriva con l'installer. Per ogni prodotto: codice a barre, nome, marca, kcal, grassi, proteine, carboidrati e sale per 100 g, e la porzione della confezione; un indice FTS5 per la ricerca per nome e marca, senza badare ad accenti e maiuscole. Il sale è nel file ma il protocollo per ora non lo usa. Pesa circa 40 MB, per circa 220 mila prodotti.
- **Come si fa:** `coach/nucleo/bin/genera_catalogo_cibo.dart` legge l'esportazione CSV di Open Food Facts (`en.openfoodfacts.org.products.csv.gz`, circa 1,5 GB compressi) mentre la scarica, senza salvarla, e tiene i prodotti con `en:italy` tra i paesi, un nome, un codice da 8 a 14 cifre e le calorie. Le calorie vengono da `energy-kcal_100g`, altrimenti da `energy-kj_100g` diviso 4,184; i valori fuori dagli intervalli del §8.8 si scartano. Si rigenera a ogni rilascio, e la build del programma lo mette accanto all'eseguibile (`coach/app/windows/cibo`, fuori da git).
- **Ricerca:** l'app mostra subito i cibi già usati che corrispondono a quello che l'atleta scrive (§8.8). Premendo invio chiede al coach `GET /v1/cibo` (§6.3) e aggiunge i prodotti che non ha già. Non si interroga il coach a ogni lettera, per restare nel limite di richieste.
- **Codice a barre:** la fotocamera legge il codice sul telefono, con una libreria che non usa la rete. L'app lo cerca tra i cibi già usati e poi con `GET /v1/cibo/<codice>`; se nessuno ce l'ha, l'atleta scrive l'alimento con il codice già compilato.
- **Licenza:** il catalogo è un database derivato da Open Food Facts, sotto licenza ODbL. Si distribuisce intero, così com'è, dentro l'installer; la pagina dei download dice dove si trova e con quale licenza, e la sezione Cibo dell'app cita Open Food Facts e la licenza.

| Situazione | Messaggio |
| --- | --- |
| Nessuna rete o Tor non parte | «Ricerca non disponibile ora: sei offline o Tor non parte. Puoi usare i cibi già usati o scriverlo tu.» |
| PC del coach spento o non raggiungibile | «Il PC del coach non è raggiungibile: la ricerca funziona quando è acceso. Intanto puoi usare i cibi già usati o scriverlo tu.» |
| Programma senza catalogo, o precedente alla 1.6.0 | «Il programma del coach non ha il catalogo dei cibi: deve aggiornarlo. Intanto puoi scriverlo tu.» |
| Codice sconosciuto | «Questo prodotto non è nel catalogo del coach. Puoi scriverlo tu.» |
| HTTP 429 o 503 | «Troppe ricerche. Riprova tra un minuto.» |
| Altri errori | «La ricerca non è riuscita. Riprova più tardi.» |

## 11. Sicurezza e privacy

### 11.1 Chi vede cosa

| Soggetto | Cosa vede |
| --- | --- |
| Sviluppatore | Niente |
| Relay Tor | Traffico cifrato. Nessun relay conosce insieme le due estremità |
| Directory degli onion service | Descrittori cifrati |
| Chi conosce l'indirizzo onion ma non ha una chiave autorizzata | Non può decifrare il descrittore né raggiungere il servizio |
| Gestore della rete del coach o dell'atleta | Che si usa Tor, non con chi si parla |
| Atleta | Le proprie schede e i propri log. Non vede gli altri atleti né l'indirizzo IP del coach |
| Coach | I dati dei propri atleti. Non vede l'indirizzo IP degli atleti |
| Chi accede al PC del coach | Tutti i dati del coach. È fuori dal modello di minaccia; si consiglia la cifratura del disco |
| Chi ruba il telefono del coach | Niente, se non supera il blocco dell'app prima che il coach revochi il telefono dal PC. Sul telefono restano solo i messaggi in coda e il token (§16.4) |
| Il sito di un video di un esercizio (per esempio YouTube) | Quando l'atleta tocca «Guarda il video», l'indirizzo IP del telefono e quale video guarda: il video arriva senza Tor. Non vede il coach né il collegamento con lui |

### 11.2 Misure

- L'indirizzo onion nel QR è la chiave pubblica del coach: l'app sa di parlare con lui. L'indirizzo di un coach non cambia mai se non con un nuovo abbinamento.
- Il controllo d'accesso è doppio: la client authorization decide chi può raggiungere il servizio, il token identifica il dispositivo. La revoca vale subito per il token e, a livello Tor, dalla ripubblicazione del servizio.
- Inviti monouso e a scadenza. Il segreto d'invito resta sul PC solo finché l'invito è aperto, il token solo come hash; i confronti avvengono in tempo costante.
- Ogni richiesta è validata contro lo schema e rispetta i limiti del §6.2.
- Via onion il programma espone solo gli endpoint del §6.3 e, al solo telefono del coach, quelli del §16.3. Nessun file, nessuna funzione di amministrazione: il telefono legge i dati e scrive messaggi, ma non tocca schede, atleti, chiavi o backup.
- I log tecnici restano in locale, non contengono token, chiavi né il contenuto di schede e log, e ruotano a 10 MB.
- Nessuna libreria di terze parti che usi la rete (analisi, segnalazione errori, pubblicità).

### 11.3 Dati personali

I dati restano sul PC del coach e sui telefoni degli atleti. Lo sviluppatore non ne riceve nessuno. Il programma permette di esportare e cancellare tutti i dati di un atleta; l'app permette all'atleta di esportare e cancellare i propri.

Il peso è un dato sulla salute: lo riceve solo il coach a cui l'atleta sceglie di condividerlo, e l'atleta può ritirarlo in ogni momento (§8.5). Lo stesso vale per il diario del cibo (§8.8). Le ricerche nel catalogo dei cibi arrivano solo al coach, che vede già il diario se l'atleta lo condivide (§10.3).

Anche le risposte ai questionari e le foto del corpo possono essere dati sulla salute. Arrivano solo al coach che ha mandato il questionario, passando da Tor; sul suo PC stanno nell'archivio e nel backup cifrato. Chi accede al PC del coach le vede, come il resto (§11.1).

## 12. Requisiti non funzionali

- Durata di una sync con Tor già avviato: sotto i 15 s nel 90% dei casi.
- Durata di una sync con avvio di Tor (stato salvato): sotto i 45 s nel 90% dei casi.
- Traffico applicativo di una sync tipica (nessuna scheda nuova, fino a 5 log): sotto i 50 KB, escluso il traffico proprio di Tor.
- Capacità: fino a 200 atleti per coach.
- Il programma del coach usa una quantità trascurabile di CPU quando nessuno si collega.
- Nessuna perdita di log se la sync si interrompe in qualsiasi punto (§7.3).
- Interfacce in italiano, con i testi in file di risorse pronti per la traduzione.
- Il programma accetta tutte le versioni dell'app con la stessa versione maggiore del protocollo. `versione_app_minima` si alza solo per correzioni di sicurezza.

## 13. Limiti noti e rischi

- Il PC del coach deve essere acceso. Con il PC spento o sospeso nessuno sincronizza: gli atleti si allenano con la scheda salvata e i log aspettano.
- Su iOS la sync in background non è garantita; nella pratica avviene con l'app aperta.
- Le notifiche push non sono possibili: l'atleta vede una scheda nuova solo dopo una sync.
- Alcune reti (aziendali, scolastiche, di alcuni paesi) bloccano Tor. La v1 non supporta i bridge: l'atleta deve usare un'altra rete.
- Ogni connessione richiede qualche secondo.
- Senza lo sviluppatore il sistema continua a funzionare, ma non per sempre. La rete Tor può smettere di accettare versioni troppo vecchie del client e gli store possono nascondere le app non aggiornate ai loro requisiti. L'opzione per usare un `tor` esterno (§9.2) allunga la vita del programma del coach.
- Se il coach perde la chiave d'identità senza un backup, cambia indirizzo e tutti gli atleti devono riabbinarsi. Lo storico sul PC è perso; gli atleti conservano i propri log sul telefono.
- Due PC attivi con la stessa identità si contendono il servizio e dividono i log tra due archivi.
- La ricerca dei cibi ha bisogno del PC del coach acceso, come la sync. Il catalogo è fermo al rilascio del programma: i prodotti usciti dopo mancano finché non si aggiorna. I dati di Open Food Facts li inseriscono volontari e possono essere incompleti, soprattutto per gli alimenti sfusi. Senza catalogo il diario funziona con i cibi già usati e gli alimenti scritti a mano.
- L'app del coach (§16) dipende dal PC come gli atleti: con il PC spento o sospeso non mostra niente e i messaggi scritti restano in coda. Senza notifiche push, con l'app chiusa i messaggi si scoprono con la sync in background, che Android può rimandare.

## 14. Fuori ambito per la v1

- Casella postale sempre accesa sul modello di Briar. Richiederà una nuova versione del protocollo.
- Più dispositivi attivi per lo stesso atleta.
- Chat o commenti tra coach e atleta.
- Video che passano da Tor, e foto fuori dai questionari. I link ai video degli esercizi (§8.1) e le foto dei questionari (§8.6) ci sono.
- Bridge Tor (obfs4, Snowflake).
- Accesso del coach da più PC. Dal telefono c'è l'app del coach (§16), senza editor delle schede e senza video.
- Telefono del coach come server, al posto del PC: le schermate dell'app leggono da un'unica interfaccia, così si potrà aggiungere, ma va prima provato quanto Tor resiste in background su Android.
- Aggiornamento automatico del programma del coach.
- Per il cibo: banche dati degli alimenti sfusi (CIQUAL, CREA), aggiornamento del catalogo senza un nuovo rilascio, il sale nel protocollo, piani alimentari scritti dal coach, foto dei pasti.
- Importazione di dati da altri sistemi o dalla versione basata su Nostr.

## 15. Riferimenti

- OnionShare: Tor incluso in un programma desktop, onion service persistenti, client authorization gestita dalla porta di controllo.
- Briar: Tor incorporato su Android, sincronizzazione quando i dispositivi sono online insieme, casella postale.
- Specifiche di Tor: rend-spec-v3 (client authorization), control-spec (`ADD_ONION`, `DEL_ONION`, `HS_DESC`, `STATUS_GENERAL`), proposta 304 (errori SOCKS estesi).
- Esportazioni di Open Food Facts (world.openfoodfacts.org/data) e licenza ODbL del database.

## 16. App del coach

L'app con cui il coach, lontano dal PC, risponde agli atleti e guarda i loro dati. Si aggiunge entro la v1 del protocollo.

### 16.1 Regole

- Il programma del coach resta l'unico server e l'unico archivio. L'app ne è un client, come quella dell'atleta: non esiste un secondo archivio da riconciliare (§13).
- Il coach ha al massimo un telefono attivo. Collegarne uno nuovo revoca il precedente.
- Il telefono del coach non è un dispositivo (§3): sta in tabelle proprie, con token propri. Il token di un atleta non vale sugli endpoint del §16.3, e il token del coach non vale su quelli del §6.3.
- Può leggere i dati degli atleti, scrivere messaggi e segnare come letti messaggi e risposte. Non può creare o modificare atleti e schede, mandare questionari, né toccare inviti, chiavi o backup.
- I video della chat restano sul PC: l'app dice che c'è un video e che si guarda da lì.

### 16.2 Abbinamento

- Il coach apre «Collega il mio telefono» nelle impostazioni del programma, che mostra un QR valido 1 ora. Il QR non si copia e non si manda: questo telefono vede i dati di tutti gli atleti, e il QR sullo schermo costringe a essere davanti al PC.
- Formato: `opencoach://telefono?v=1&o=<onion>&i=<id>&s=<segreto>&k=<chiave>`, con gli stessi campi del §5.2. L'app dell'atleta non lo accetta, e l'app del coach non accetta gli inviti degli atleti.
- Il flusso è quello del §5.3, sugli endpoint del §16.3. Ripetere l'abbinamento con la stessa chiave dà un token nuovo; con un'altra chiave dà 409 `invito_in_uso` e il programma lo segnala sempre al coach.
- Il programma avvisa sempre quando un telefono si collega, mostra quello collegato e permette di revocarlo. La revoca vale come quella di un dispositivo (§9.3). «Reimposta identità» revoca anche questo telefono.

### 16.3 Endpoint

Tutti con `Authorization: Bearer <token>` del telefono del coach, tranne l'abbinamento. Convenzioni e codici di stato sono quelli del §6, con un limite proprio di 120 richieste al minuto. Un `<id>` di atleta sconosciuto dà 404.

| Richiesta | Corpo o parametri | Risposta |
| --- | --- | --- |
| `POST /v1/coach/abbinamento` | Come `POST /v1/abbinamento`, senza token | `{ "telefono_id", "token", "nome_coach" }` |
| `POST /v1/coach/abbinamento/conferma` | Vuoto | 204. Idempotente |
| `DELETE /v1/coach/telefono` | Vuoto | 204. Il coach scollega il telefono dall'app |
| `GET /v1/coach/atleti` | | `{ "atleti": [ … ], "impronta": "…" }`: gli atleti non archiviati, in ordine di nome. Per ognuno `id`, `nome`, `telefono_collegato`, `ultimo_contatto`, `non_letti`, `risposte_nuove`, `ultimo_messaggio`, `ultimo_allenamento` |
| `GET /v1/coach/atleti/<id>` | | Gli stessi campi, più `note`, `allenamenti_totali`, `schede` (`id`, `titolo`, `stato`, `revisione`, `ricevuta_il`) |
| `GET /v1/coach/atleti/<id>/messaggi` | `?prima=<id>` facoltativo | `{ "messaggi": [ … ], "altri": bool }`: gli ultimi, dal più vecchio, fino a 200 e sotto i limiti del §6.2 |
| `POST /v1/coach/atleti/<id>/messaggi` | `{ "id", "testo" }`, con `id` UUID generato dall'app | Il messaggio. Idempotente: rimandare lo stesso `id` non lo duplica. 409 se l'`id` è già usato da altro |
| `POST /v1/coach/atleti/<id>/messaggi/letti` | Vuoto | 204 |
| `GET /v1/coach/atleti/<id>/allenamenti` | `?prima=<id>` facoltativo | `{ "allenamenti": [ … ], "altri": bool }`: i log dal più recente, fino a 50 e sotto i limiti del §6.2 |
| `GET /v1/coach/atleti/<id>/pesi` | | `{ "pesi": [ { "giorno", "kg" } ] }`, dal più vecchio |
| `GET /v1/coach/atleti/<id>/cibo` | `?prima=<giorno>` facoltativo | `{ "obiettivo": { … } \| null, "giornate": [ { "giorno", "voci": [ … ] } ], "altri": bool }`: l'obiettivo (§8.8) e le giornate non eliminate dalla più recente, fino a 28 e sotto i limiti del §6.2. Senza cibo condiviso `giornate` è vuoto |
| `GET /v1/coach/atleti/<id>/questionari` | | `{ "questionari": [ { "id", "titolo", "contenuto", "inviato_il", "stato", "risposta", "risposto_il", "letto" } ], "altri": bool }`, dal più recente |
| `POST /v1/coach/questionari/<id>/letto` | Vuoto | 204 |
| `GET /v1/coach/foto/<id>` | | La foto, `image/jpeg` |
| `POST /v1/coach/attendi` | `{ "impronta": "…", "attesa_s": 25 }` | `{ "novita": bool }`. Vero appena l'impronta è diversa, falso dopo l'attesa, al massimo 25 s. Come `POST /v1/attendi`: una per telefono, non cambia niente |

L'`impronta` riassume lo stato dei dati che l'app mostra: messaggi, non letti, log, pesi, giornate del cibo, obiettivi, questionari. Due impronte uguali vogliono dire che non c'è niente di nuovo da chiedere.

Un messaggio scritto dal telefono è uguale a uno scritto dal PC: l'autore è il coach e arriva all'atleta con la sync (§7.3).

### 16.4 Comportamento dell'app

- **Blocco:** all'apertura, e dopo 5 minuti in background, l'app chiede l'impronta o il blocco schermo del telefono. Se il telefono non ha un blocco schermo l'app lo dice e resta usabile.
- **Sul telefono:** token e chiave nella cassaforte (§4), i messaggi in coda cifrati allo stesso modo, e per ogni atleta quanti non letti ha già annunciato. Tutto il resto, nomi e messaggi compresi, sta in memoria e sparisce con il processo. Backup del sistema disattivati.
- **Coda:** un messaggio scritto con il PC irraggiungibile resta in coda e parte da solo, in primo piano o in background, con lo stesso `id`. L'app lo mostra come «in attesa».
- **In primo piano:** l'app tiene un `POST /v1/coach/attendi` in sospeso e rilegge i dati appena cambiano. Se il coach non è raggiungibile ritenta dopo 30 s, 2 e 5 minuti.
- **In background:** lavoro periodico con WorkManager, predefinito ogni 15 minuti (impostabile: disattivato, 15, 30 o 60 minuti), solo con rete e batteria non scarica. Manda i messaggi in coda e controlla le novità.
- **Notifiche:** dicono chi ha scritto o risposto e quanti sono, mai il testo: possono comparire sullo schermo bloccato.
- **Cibo:** nella pagina dell'atleta, se lo condivide, calorie e macronutrienti di ogni giorno con l'obiettivo; aprendo un giorno, i pasti con le voci, i grammi e la fonte dei valori. In sola lettura, come il resto (§16.1): l'obiettivo si fissa dal PC.
- **Telefono revocato:** alla risposta 401 l'app cancella token e coda e torna alla schermata di collegamento.

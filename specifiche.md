# Open Coach — Specifiche v1

Versione 1.0 · 18 ottobre 2026

Questo documento definisce la versione 1 del sistema descritto in «Architettura senza server: onion service del coach». Sostituisce l'architettura precedente basata su relay Nostr e PWA.

## 1. Principi

1. Il programma del coach è l'unico server del sistema e serve solo i propri atleti, tramite un onion service Tor v3 incluso nel programma.
2. Lo sviluppatore non gestisce infrastruttura: niente server, account, telemetria, segnalazione automatica degli errori o controllo degli aggiornamenti. Tutto il traffico di rete dei due programmi passa per Tor.
3. Ogni installazione del programma del coach è indipendente, con chiavi, indirizzo e dati propri. Nessuna funzione dipende dall'esistenza del progetto.
4. L'app dell'atleta funziona offline; la rete serve solo a sincronizzare.
5. Ogni tipo di dato ha un solo autore: le schede le scrive il coach, i log l'atleta. Non ci sono conflitti di scrittura da risolvere.
6. La sincronizzazione parte sempre dall'app dell'atleta.

## 2. Componenti

| Componente | Piattaforme | Ruolo |
| --- | --- | --- |
| Programma del coach | Windows 10+, macOS 12+, Linux x86_64 | Server: Tor, onion service, API HTTP, archivio, interfaccia del coach |
| App dell'atleta | Android 8.0+ (API 26), iOS 16+ | Client: Tor incorporato, archivio locale, esecuzione delle schede |
| Rete Tor | — | Trasporto. Non è un componente del progetto |

Distribuzione:

- App: Google Play e App Store; F-Droid facoltativo.
- Programma del coach: installer scaricabili dalla pagina delle release del progetto. Su Windows firmato Authenticode; su macOS firmato e notarizzato, compreso l'eseguibile `tor`; su Linux AppImage.

## 3. Glossario

| Termine | Significato |
| --- | --- |
| Coach | Utente del programma desktop. Un'installazione corrisponde a un coach. |
| Atleta | Persona seguita dal coach. Esiste solo nell'archivio del coach, non ha un account. |
| Dispositivo | Telefono dell'atleta abbinato al coach. In v1 un atleta ha al massimo un dispositivo attivo. |
| Invito | Autorizzazione monouso e a scadenza per abbinare un dispositivo a un atleta. Si consegna come QR o link. |
| Scheda | Programma di allenamento scritto dal coach per un atleta, composto da sedute. |
| Revisione | Versione pubblicata di una scheda. Ogni ripubblicazione crea una revisione nuova. |
| Seduta | Singolo allenamento previsto dalla scheda (es. «Giorno A»), composto da esercizi. |
| Log | Registrazione di un allenamento eseguito, scritta dall'atleta. |
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

Ripetere `POST /v1/abbinamento` con la stessa chiave di dispositivo prima della conferma restituisce un token nuovo e invalida il precedente: copre il caso in cui la risposta si perda.

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
- La client authorization v3 è sempre attiva: solo chi possiede una chiave autorizzata (invito aperto o dispositivo attivo) può decifrare il descrittore e raggiungere il servizio.
- L'app si collega via SOCKS5 lasciando la risoluzione del nome a Tor, con gli errori SOCKS estesi attivi (`ExtendedErrors`) per distinguere i guasti (§7.5).

### 6.2 Convenzioni

- Corpi in JSON UTF-8 con `Content-Type: application/json`, chiavi in snake_case.
- Date e ore in ISO 8601 con fuso orario (`2026-10-21T18:30:00+02:00`), date semplici `YYYY-MM-DD`. Id in UUID v4 minuscolo.
- Autenticazione con `Authorization: Bearer <token>` su tutte le chiamate tranne `GET /v1/info` e `POST /v1/abbinamento`. Ogni dato letto o scritto con un token è limitato all'atleta di quel token.
- La versione maggiore del protocollo è nel percorso (`/v1`). Entro la stessa versione si aggiungono solo campi facoltativi, ed entrambe le parti ignorano i campi sconosciuti.
- Limiti: richiesta e risposta fino a 2 MiB (oltre si pagina), un log fino a 64 KiB, una scheda fino a 256 KiB, al massimo 100 log per richiesta.
- Frequenza: al massimo 30 richieste al minuto per dispositivo, 10 tentativi al minuto in totale su `POST /v1/abbinamento`, 10 sync contemporanee.
- Timeout lato app: 90 s per stabilire la connessione, 60 s per ricevere la risposta. Nella lettura dell'invito (§5.3, punto 3) ogni tentativo dura al massimo 30, poi 45, poi 60 s, e i tentativi si ripetono per circa 2 minuti: la prima connessione di un Tor appena avviato a volte resta appesa, mentre una nuova riesce in pochi secondi.
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
  "altro": false
}
```

- Il server tratta prima i log ricevuti, poi calcola le modifiche da restituire.
- La risposta è completa (`completo: true`) se `cursore` è null o se `epoca` è null o diversa da quella attuale. In quel caso `schede` contiene tutte le schede pubblicate e archiviate dell'atleta e `log` tutti i suoi log, compresi gli eliminati nella forma `{ "id", "rev", "eliminato": true }`.
- In una risposta incrementale `schede` contiene solo le schede cambiate dopo il cursore e `log` è vuoto.
- Con `altro: true` l'app ripete la chiamata con il nuovo cursore e senza log, finché `altro` è false.
- Codici d'errore per `log_rifiutati`: `non_valido` (schema), `troppo_grande`, `altro_atleta` (id già usato da un altro atleta).

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
2. Prende dalla coda fino a 100 log, cioè i log con `rev` maggiore dell'ultima `rev` confermata dal coach.
3. Chiama `POST /v1/sync` con il cursore e l'epoca salvati.
4. Con una risposta incrementale applica in un'unica transazione locale: schede nuove o cambiate, schede eliminate, log confermati (solo se la `rev` locale è ancora quella inviata), nuovo cursore.
5. Se `altro` è true o restano log in coda, torna al punto 2.

Con una risposta completa l'app accumula tutte le pagine e le applica insieme solo dopo l'ultima:

- sostituisce l'insieme delle schede con quello ricevuto;
- inserisce i log che non ha, e prende la versione del coach se ha `rev` maggiore;
- rimette in coda i log locali assenti dalla risposta o presenti con `rev` minore. Così, dopo un ripristino del coach da backup, i telefoni reinviano i log arrivati dopo quel backup;
- salva cursore ed epoca.

Se una sync completa si interrompe, la successiva ricomincia da capo.

Nessun dato va perso se la connessione cade in qualsiasi punto: il programma tratta i log in modo idempotente, e l'app avanza il cursore e svuota la coda solo dopo aver salvato la risposta.

I log rifiutati restano sul telefono, segnalati all'atleta, e non vengono ritentati in automatico.

### 7.4 Quando parte la sync

App in primo piano:

- all'apertura e al ritorno in primo piano;
- subito dopo il salvataggio, la modifica o l'eliminazione di un log;
- con il tasto «Sincronizza ora» o trascinando per aggiornare;
- ogni 10 minuti finché l'app resta aperta.

Se il coach non è raggiungibile, l'app ritenta dopo 30 s, 2 minuti e 5 minuti, poi aspetta la prossima occasione.

App in background:

- Android: lavoro periodico con WorkManager, predefinito ogni 60 minuti (impostabile: disattivato, 30 minuti, 1, 3 o 6 ore), solo con rete disponibile e batteria non scarica. Una sync iniziata in primo piano prosegue come lavoro accelerato se l'app viene chiusa.
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
  "valida_dal": "2026-10-20",
  "valida_al": "2026-11-16",             // facoltativo
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

Segreto e chiave privata d'invito si cancellano quando l'invito si chiude.

### 8.4 Archivio dell'app

SQLite nello spazio privato dell'app. Su iOS i file usano la classe di protezione `CompleteUntilFirstUserAuthentication`, così la sync in background può leggerli.

Per ogni coach: indirizzo, nome, id dell'atleta e del dispositivo, cursore, epoca, data dell'ultima sync; le sue schede; i log, ciascuno con la `rev` locale e l'ultima `rev` confermata. Chiavi e token sono conservati come descritto al §4.

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
- generare, mostrare di nuovo e annullare un invito;
- vedere per ogni atleta stato, dispositivo, versione dell'app e ultimo contatto;
- revocare il dispositivo: il token smette di valere subito e il servizio viene ripubblicato senza la sua chiave;
- esportare i dati di un atleta in JSON (anagrafica, schede con le revisioni, allenamenti) e in CSV (una riga per serie, nel formato che Excel in italiano apre direttamente). Le note private entrano nell'esportazione solo se il coach lo chiede, perché il file può finire all'atleta.

Schede:

- creare, modificare e duplicare, anche per un altro atleta;
- pubblicare: crea una revisione che l'atleta riceve alla prossima sync. Le modifiche successive restano in bozza fino alla ripubblicazione;
- archiviare ed eliminare;
- vedere per ogni revisione se l'atleta l'ha ricevuta e quando.

Log:

- elenco per atleta in ordine di esecuzione, con il dettaglio di ogni seduta e il confronto con la prescrizione della revisione usata;
- segnalazione dei log eseguiti su una revisione non più attuale;
- i log sono in sola lettura.

Notifiche desktop, disattivabili: log ricevuto, abbinamento completato, invito usato da un secondo telefono.

### 9.4 Backup e ripristino

- Il backup è un file unico, cifrato con una passphrase scelta dal coach (Argon2id e XChaCha20-Poly1305), che contiene identità, archivio e impostazioni.
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

- Primo avvio: «Scansiona il QR del tuo coach», oppure incolla il codice. Nessun account, nessuna registrazione.
- Schede: elenco per coach, dettaglio delle sedute, scelta della seduta da eseguire, avviso quando arriva una nuova revisione.
- Esecuzione: per ogni esercizio le serie sono precompilate con la prescrizione; l'atleta inserisce ripetizioni, carico, durata e RPE effettivi, usa un timer di recupero e scrive note. Può aggiungere esercizi non previsti o registrare un allenamento libero. Al salvataggio il log entra in coda e parte una sync.
- Storico: i propri log, modificabili ed eliminabili. Ogni modifica incrementa `rev` e rimette il log in coda.
- Stato della sync come al §7.5, con il tasto «Sincronizza ora».
- Impostazioni: coach collegati (nome, indirizzo, ultima sync); scollegarsi da un coach, che chiama `DELETE /v1/dispositivo` se il coach è raggiungibile e poi, dopo conferma, cancella i dati locali di quel coach; frequenza della sync in background (Android); esportazione dei propri dati in JSON.
- L'app può essere abbinata a più coach contemporaneamente. Schede e log restano separati per coach.
- Dopo una revoca le schede e i log di quel coach restano consultabili ed esportabili, ma non si sincronizzano più.

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

### 11.2 Misure

- L'indirizzo onion nel QR è la chiave pubblica del coach: l'app sa di parlare con lui. L'indirizzo di un coach non cambia mai se non con un nuovo abbinamento.
- Il controllo d'accesso è doppio: la client authorization decide chi può raggiungere il servizio, il token identifica il dispositivo. La revoca vale subito per il token e, a livello Tor, dalla ripubblicazione del servizio.
- Inviti monouso e a scadenza. Il segreto d'invito resta sul PC solo finché l'invito è aperto, il token solo come hash; i confronti avvengono in tempo costante.
- Ogni richiesta è validata contro lo schema e rispetta i limiti del §6.2.
- Via onion il programma espone solo gli endpoint del §6.3. Nessun file, nessuna funzione di amministrazione.
- I log tecnici restano in locale, non contengono token, chiavi né il contenuto di schede e log, e ruotano a 10 MB.
- Nessuna libreria di terze parti che usi la rete (analisi, segnalazione errori, pubblicità).

### 11.3 Dati personali

I dati restano sul PC del coach e sui telefoni degli atleti. Lo sviluppatore non ne riceve nessuno. Il programma permette di esportare e cancellare tutti i dati di un atleta; l'app permette all'atleta di esportare e cancellare i propri.

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

## 14. Fuori ambito per la v1

- Casella postale sempre accesa sul modello di Briar. Richiederà una nuova versione del protocollo.
- Più dispositivi attivi per lo stesso atleta.
- Chat o commenti tra coach e atleta.
- Allegati multimediali (video, foto).
- Bridge Tor (obfs4, Snowflake).
- Accesso del coach da più PC o dal telefono.
- Aggiornamento automatico del programma del coach.
- Importazione di dati da altri sistemi o dalla versione basata su Nostr.

## 15. Riferimenti

- OnionShare: Tor incluso in un programma desktop, onion service persistenti, client authorization gestita dalla porta di controllo.
- Briar: Tor incorporato su Android, sincronizzazione quando i dispositivi sono online insieme, casella postale.
- Specifiche di Tor: rend-spec-v3 (client authorization), control-spec (`ADD_ONION`, `DEL_ONION`, `HS_DESC`, `STATUS_GENERAL`), proposta 304 (errori SOCKS estesi).

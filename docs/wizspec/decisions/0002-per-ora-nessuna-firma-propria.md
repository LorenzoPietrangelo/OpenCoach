# Per ora nessuna firma propria per APK e installer

Per la prima distribuzione l'APK resta firmato con la chiave di debug del PC che lo compila e
l'installer Windows non ha la firma Authenticode. Le specifiche (§2) chiedono entrambe le firme, ma
per ora si rinuncia a creare e custodire una chiave Android e a pagare o ottenere un certificato.

## Consequences

- Ogni APK va compilato su un PC che ha questa chiave di debug
  (`C:\Users\loren\.android\debug.keystore`, alias `androiddebugkey`, certificato SHA-256
  `C0:E9:2F:D3:…:1F:71:89:D8`, valido fino al 2056): con un'altra chiave, CI compresa, non si
  installa come aggiornamento. Su un altro PC basta rimettere il file nello stesso percorso. Il
  file va salvato fuori dal PC, mai in una repo: perderlo, o passare in seguito a una chiave
  propria, costringe ogni atleta a disinstallare l'app e a riabbinarsi.
- Chi ottiene quel file può firmare un aggiornamento che i telefoni accettano: la sua password è
  pubblica.
- L'installer parte dopo l'avviso di SmartScreen, ma non parte sui PC con Smart App Control attivo.
  La pagina dei download deve dirlo.
- La firma Windows gratuita di SignPath Foundation richiede codice open source: la scelta del
  certificato dipende da quella di rendere pubblico il codice, che per ora resta privato (vedi
  0003).

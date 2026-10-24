# Open Coach – pagina dei download

Pagina da cui coach e atleti scaricano l'installer del programma del coach (Windows) e l'APK
dell'app dell'atleta (Android). È pubblica ma non pubblicizzata: chiede ai motori di ricerca di
non indicizzarla, e la trova solo chi ne riceve il link.

**Non modificare i file a mano.** Questa cartella la genera `strumenti/rilascio.ps1` nella repo
del codice, partendo dal modello in `strumenti/download/`: le modifiche vanno fatte lì.

| File | Contenuto |
| --- | --- |
| `index.html` | la pagina, con versione, data e impronte SHA-256 dei file |
| `condizioni.html` | le condizioni d'uso, raggiungibili dal link sotto i download e nel piè di pagina |
| `vercel.json` | header di sicurezza e download come allegato |
| `favicon.png`, `apple-touch-icon.png` | il logo di Open Coach per le schede del browser e la schermata Home |
| `file/` | l'installer e l'APK dell'ultimo rilascio |
| `immagini/` | le foto della pagina, da Unsplash (licenza Unsplash; fonti in `strumenti/download/immagini/FONTI.md` nella repo del codice) |

## Collegarla a Vercel (una volta sola)

1. Crea su GitHub una repo per questa cartella. Può essere privata: Vercel la legge lo stesso.
2. Su Vercel: **Add New → Project**, importa la repo e lascia **Framework Preset: Other**, senza
   comando di build, con la radice della repo come cartella di output.
3. Il nome del progetto diventa l'indirizzo della pagina: `<nome>.vercel.app`.

Da lì Vercel pubblica la pagina a ogni push sul ramo principale.

## Un nuovo rilascio

Dalla repo del codice:

```
powershell -ExecutionPolicy Bypass -File strumenti\rilascio.ps1 -Versione 1.1.0
```

Lo script compila tutto, copia qui i file con le impronte e conserva una copia del rilascio in
`C:\dev\opencoach-rilasci\<versione>`. Poi, in questa cartella, fai commit e push.

La pagina offre solo l'ultima versione, quindi la storia di questa repo non serve, e i file
grossi la farebbero crescere di circa 115 MB a ogni rilascio. Conviene sostituirla ogni volta con
un solo commit:

```
git checkout --orphan nuovo
git add -A
git commit -m "Rilascio 1.1.0"
git branch -D main
git branch -m main
git push --force origin main
```

GitHub rifiuta i file oltre 100 MB e avvisa sopra i 50 MB: l'APK ne pesa circa 90.

## Limiti di Vercel (piano Hobby)

File fino a 100 MB, 100 GB di traffico al mese (circa 900 download dell'APK), solo uso personale
non commerciale.

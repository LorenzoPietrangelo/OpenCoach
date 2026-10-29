<#
.SYNOPSIS
  Prepara un rilascio di Open Coach per la pagina dei download.

.DESCRIPTION
  Compila il programma del coach per Windows e l'app dell'atleta per Android, crea l'installer,
  copia i due file nella cartella della pagina dei download con le loro impronte SHA-256 e ne
  conserva una copia nell'archivio dei rilasci. La cartella della pagina si carica poi sulla sua
  repo GitHub, collegata a Vercel (decisione 0003).

  Il numero di versione deve essere già lo stesso nei due pubspec.yaml e nelle costanti
  versioneProgramma e versioneApp: lo script lo controlla, non lo cambia.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File strumenti\rilascio.ps1 -Versione 1.1.0

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File strumenti\rilascio.ps1 -Versione 1.0.0 -SenzaCompilare
#>
param(
  [Parameter(Mandatory = $true)][string]$Versione,
  [string]$Sito = 'C:\dev\opencoach-download',
  [string]$Archivio = 'C:\dev\opencoach-rilasci',
  [string]$Flutter = 'C:\flutter\bin\flutter.bat',
  [string]$Iscc = (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
  [string]$AndroidSdk = (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
  # Usa i file già compilati: serve a rigenerare la pagina senza ricompilare.
  [switch]$SenzaCompilare
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$modello = Join-Path $PSScriptRoot 'download'
$italiano = [Globalization.CultureInfo]::GetCultureInfo('it-IT')

# Certificato della chiave di debug con cui sono firmati gli APK già distribuiti (decisione 0002):
# un APK firmato con un'altra chiave non si installa come aggiornamento.
$certificatoAtteso = 'c0e92fd35cbeeee8fc871b7a8233504b9452aefb8b8557d138562f5a1f7189d8'

function Ferma([string]$messaggio) {
  Write-Host "`n$messaggio" -ForegroundColor Red
  exit 1
}

function Passo([string]$testo) {
  Write-Host "`n== $testo" -ForegroundColor Cyan
}

function Esegui([string]$cartella, [string]$comando, [string[]]$argomenti) {
  Write-Host "> $comando $($argomenti -join ' ')"
  Push-Location $cartella
  try {
    & $comando @argomenti
    if ($LASTEXITCODE -ne 0) { Ferma "Non riuscito: $comando $($argomenti -join ' ') (codice $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
}

function Dimensione([long]$byte) {
  [string]::Format($italiano, '{0:N1} MB', $byte / 1e6)
}

if ($Versione -notmatch '^\d+\.\d+\.\d+$') { Ferma "Versione non valida: $Versione (es. 1.1.0)" }

Passo "Versioni nel codice"
$versioni = @(
  @('coach/app/pubspec.yaml', '(?m)^version:\s*([0-9.]+)\+'),
  @('atleta/app/pubspec.yaml', '(?m)^version:\s*([0-9.]+)\+'),
  @('coach/app/lib/main.dart', "versioneProgramma = '([^']+)'"),
  @('atleta/app/lib/main.dart', "versioneApp = '([^']+)'")
)
foreach ($v in $versioni) {
  $testo = [IO.File]::ReadAllText((Join-Path $repo $v[0]))
  $trovata = [regex]::Match($testo, $v[1])
  if (-not $trovata.Success) { Ferma "Versione non trovata in $($v[0])" }
  $valore = $trovata.Groups[1].Value
  Write-Host ("{0,-28} {1}" -f $v[0], $valore)
  if ($valore -ne $Versione) {
    Ferma "In $($v[0]) la versione è $valore, non ${Versione}: aggiornala prima del rilascio."
  }
}

$buildTools = Get-ChildItem (Join-Path $AndroidSdk 'build-tools') -Directory |
  Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending |
  Select-Object -First 1
if ($null -eq $buildTools) { Ferma "Build-tools di Android non trovati in $AndroidSdk" }
$aapt2 = Join-Path $buildTools.FullName 'aapt2.exe'
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'

$coach = Join-Path $repo 'coach\app'
$atleta = Join-Path $repo 'atleta\app'
$exe = Join-Path $coach "build\installer\OpenCoach-$Versione-windows-x64.exe"
$apk = Join-Path $atleta 'build\app\outputs\flutter-apk\app-release.apk'

if (-not $SenzaCompilare) {
  Passo "Controlli prima della compilazione"
  if (-not (Test-Path (Join-Path $coach 'windows\tor\tor.exe'))) {
    Ferma "Manca Tor in coach\app\windows\tor: copia lì la cartella tor del Tor Expert Bundle."
  }
  if (-not (Test-Path $Iscc)) { Ferma "Inno Setup non trovato: $Iscc" }
  $aperto = Get-Process OpenCoach -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$coach\build\*" }
  if ($aperto) {
    Ferma "Il programma del coach compilato è aperto e ne blocca i file: esci (area di notifica → Esci) e riprova."
  }
  Write-Host "Tutto pronto."

  Passo "Programma del coach per Windows"
  Esegui $coach $Flutter @('build', 'windows', '--release')

  Passo "Installer"
  Esegui $coach $Iscc @("/DVersione=$Versione", 'installer\opencoach.iss')

  Passo "App dell'atleta per Android"
  Esegui $atleta $Flutter @('build', 'apk', '--release')
}

Passo "Controllo dei file"
if (-not (Test-Path $exe)) { Ferma "Installer non trovato: $exe" }
if (-not (Test-Path $apk)) { Ferma "APK non trovato: $apk" }

# Windows PowerShell trasforma in errori le righe che i programmi esterni scrivono su stderr, anche
# solo avvisi: per questi due conta il codice di uscita.
$ErrorActionPreference = 'Continue'
$badging = (& $aapt2 dump badging $apk 2>$null) -join "`n"
$esitoBadging = $LASTEXITCODE
$firma = (& $apksigner verify --print-certs $apk 2>&1 | ForEach-Object { "$_" }) -join "`n"
$esitoFirma = $LASTEXITCODE
$ErrorActionPreference = 'Stop'

if ($esitoBadging -ne 0) { Ferma "aapt2 non legge l'APK: $apk" }
if ($badging -match 'application-debuggable') { Ferma "L'APK è debuggabile: serve la build release." }
$nomeVersioneApk = [regex]::Match($badging, "versionName='([^']+)'").Groups[1].Value
if ($nomeVersioneApk -ne $Versione) { Ferma "L'APK è la versione $nomeVersioneApk, non $Versione." }

if ($esitoFirma -ne 0) { Ferma "Firma dell'APK non valida:`n$firma" }
$certificato = [regex]::Match($firma, 'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)').Groups[1].Value
if ($certificato -ne $certificatoAtteso) {
  Ferma ("L'APK è firmato con un'altra chiave ($certificato): sui telefoni non si installerebbe " +
    "come aggiornamento. Metti il file debug.keystore salvato in $env:USERPROFILE\.android e ricompila.")
}
Write-Host "Installer: $exe"
Write-Host "APK:       $apk (versione $nomeVersioneApk, firmato con la chiave attesa, non debuggabile)"

Passo "Archivio del rilascio"
$nomeExe = "OpenCoach-$Versione-windows-x64.exe"
$nomeApk = "OpenCoach-atleta-$Versione.apk"
$cartellaArchivio = Join-Path $Archivio $Versione
New-Item -ItemType Directory -Force $cartellaArchivio | Out-Null
Copy-Item $exe (Join-Path $cartellaArchivio $nomeExe) -Force
Copy-Item $apk (Join-Path $cartellaArchivio $nomeApk) -Force
Write-Host $cartellaArchivio

Passo "Pagina dei download"
$cartellaFile = Join-Path $Sito 'file'
New-Item -ItemType Directory -Force $cartellaFile | Out-Null
# La pagina offre solo l'ultimo rilascio: i file dei precedenti restano nell'archivio.
Get-ChildItem $cartellaFile -File | Remove-Item -Force
Copy-Item $exe (Join-Path $cartellaFile $nomeExe)
Copy-Item $apk (Join-Path $cartellaFile $nomeApk)

$fileExe = Get-Item (Join-Path $cartellaFile $nomeExe)
$fileApk = Get-Item (Join-Path $cartellaFile $nomeApk)
$valori = @{
  '{{VERSIONE}}'       = $Versione
  '{{DATA}}'           = (Get-Date).ToString('d MMMM yyyy', $italiano)
  '{{NOME_EXE}}'       = $nomeExe
  '{{NOME_APK}}'       = $nomeApk
  '{{DIMENSIONE_EXE}}' = Dimensione $fileExe.Length
  '{{DIMENSIONE_APK}}' = Dimensione $fileApk.Length
  '{{SHA256_EXE}}'     = (Get-FileHash $fileExe.FullName -Algorithm SHA256).Hash.ToLower()
  '{{SHA256_APK}}'     = (Get-FileHash $fileApk.FullName -Algorithm SHA256).Hash.ToLower()
}
foreach ($nomePagina in @('index.html', 'novita.html', 'condizioni.html')) {
  $pagina = [IO.File]::ReadAllText((Join-Path $modello $nomePagina))
  foreach ($chiave in $valori.Keys) { $pagina = $pagina.Replace($chiave, $valori[$chiave]) }
  if ($pagina -match '\{\{[A-Z0-9_]+\}\}') { Ferma "Segnaposto non sostituito in ${nomePagina}: $($Matches[0])" }
  [IO.File]::WriteAllText((Join-Path $Sito $nomePagina), $pagina, (New-Object Text.UTF8Encoding $false))
}
Copy-Item (Join-Path $modello 'vercel.json') $Sito -Force
Copy-Item (Join-Path $modello 'README.md') $Sito -Force
# Icone della scheda del browser, dallo stesso logo del programma e dell'app (strumenti/genera_icone.dart).
Copy-Item (Join-Path $modello 'favicon.png') $Sito -Force
Copy-Item (Join-Path $modello 'apple-touch-icon.png') $Sito -Force
# Le foto stanno nella pagina, non su altri siti: nessuno oltre a Vercel vede chi la visita.
$cartellaImmagini = Join-Path $Sito 'immagini'
if (Test-Path $cartellaImmagini) { Remove-Item $cartellaImmagini -Recurse -Force }
New-Item -ItemType Directory $cartellaImmagini | Out-Null
Copy-Item (Join-Path $modello 'immagini\*.jpg') $cartellaImmagini

foreach ($file in @($fileExe, $fileApk)) {
  if ($file.Length -ge 100MB) {
    Ferma "$($file.Name) pesa $(Dimensione $file.Length): GitHub e Vercel non accettano file oltre 100 MB."
  }
}

Passo "Fatto"
Write-Host "Rilascio $Versione pronto in $Sito"
Write-Host ("  {0}  {1}  {2}" -f $nomeExe, $valori['{{DIMENSIONE_EXE}}'], $valori['{{SHA256_EXE}}'])
Write-Host ("  {0}  {1}  {2}" -f $nomeApk, $valori['{{DIMENSIONE_APK}}'], $valori['{{SHA256_APK}}'])
Write-Host "Ora, in $Sito, fai commit e push sulla repo collegata a Vercel."

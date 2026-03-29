# YouTube Search Tcl

Script Tcl per cercare video su YouTube tramite YouTube Data API v3.

## Funzionalita

- Ricerca video da query testuale
- Limite risultati configurabile
- Output con titolo e URL del video
- Utilizzabile sia come libreria Tcl che da CLI

## Requisiti

- Tcl 8.6+
- curl
- API key YouTube Data API v3

## Configurazione

Imposta la variabile ambiente con la tua chiave API:

```bash
export YOUTUBE_API_KEY="YOUR_API_KEY"
```

## Uso rapido

```bash
tclsh yt-search.tcl "lofi hip hop" 5
```

Output esempio:

```text
1. Lofi Hip Hop Mix
   https://www.youtube.com/watch?v=abc123
```

## Uso come libreria

```tcl
source yt-search.tcl
set results [youtube_search "linux tutorial" 3]
foreach item $results {
    puts [dict get $item title]
    puts [dict get $item url]
}
```

## Inizializzazione repository Git

```bash
git init
git add .
git commit -m "Initial commit: YouTube search Tcl"
```

## Creazione repository GitHub

Opzione web:
1. Crea un nuovo repository vuoto su GitHub (esempio: `youtube-search-tcl`).
2. Collega il remote e pubblica:

```bash
git remote add origin git@github.com:TUO_USERNAME/youtube-search-tcl.git
git branch -M main
git push -u origin main
```

Opzione CLI (`gh`), se installata:

```bash
gh repo create youtube-search-tcl --public --source=. --remote=origin --push
```

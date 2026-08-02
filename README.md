# homepilot-apt

Update-Kanal für **HomePilot OS**. Hier liegen ausschließlich die fertigen
Debian-Pakete (`homepilot-core`, `homepilot-agent`, `homepilot-frontend`)
und der Index dazu – der Quellcode liegt woanders.

Ausgeliefert wird über GitHub Pages:
<https://fschubi.github.io/homepilot-apt>

## Für Geräte, die schon HomePilot OS laufen haben

Auf einem installierten System richtet der ISO-Erstboot die Quelle selbst
ein. Von Hand geht es so:

```sh
sudo install -d /etc/apt/keyrings
sudo curl -fsSL https://fschubi.github.io/homepilot-apt/key.asc \
    -o /etc/apt/keyrings/homepilot.asc
echo "deb [signed-by=/etc/apt/keyrings/homepilot.asc] https://fschubi.github.io/homepilot-apt beta main" \
    | sudo tee /etc/apt/sources.list.d/homepilot.list
sudo apt-get update
```

Danach spielt das Update Center neue Versionen ein – oder `apt`:

```sh
sudo apt-get install --only-upgrade homepilot-core homepilot-agent homepilot-frontend
```

## Kanäle

| Kanal    | Für wen                                       |
|----------|-----------------------------------------------|
| `beta`   | Testgeräte. Bekommt jeden Release-Candidate.  |
| `stable` | Alle anderen. Nur freigegebene Versionen.     |

Der Kanal steht in `/etc/apt/sources.list.d/homepilot.list`; zum Wechseln
dort `beta` durch `stable` ersetzen und `apt-get update` laufen lassen.

## Wie das Repository entsteht

1. Der ISO-Build im Hauptrepo baut die drei `.deb` und committet sie
   hierher nach `pool/<kanal>/`.
2. `.github/workflows/publish.yml` erzeugt daraus den Index
   (`dists/<kanal>/main/binary-amd64/`), **signiert** `Release` mit dem
   Schlüssel aus dem Secret `GPG_PRIVATE_KEY` und veröffentlicht alles
   über Pages.
3. Je Paket und Kanal bleiben die letzten **drei** Versionen liegen – das
   Update Center kann damit auf eine vorherige Version zurückrollen.

Der Index lässt sich ohne Schlüssel auch lokal bauen und ansehen:

```sh
tools/build-repo.sh && ls _site/dists/beta
```

## Signatur

Signiert wird mit `2DD9 EE03 9C91 2B7A 8FA5  2A7C 80D6 BF94 F8B5 A789`
(`sbytedigital`). Der öffentliche Schlüssel ist `key.asc`; der private
liegt ausschließlich als GitHub-Secret vor und taucht nirgends im
Repository auf.

Eine unsignierte Quelle oder `[trusted=yes]` gehört **nie** in die
sources.list – das würde die gesamte Prüfkette aushebeln. Der Workflow
bricht ab, wenn eine Signatur fehlt oder ungültig ist.

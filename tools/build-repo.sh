#!/bin/bash
# build-repo.sh – baut aus pool/<kanal>/*.deb ein signiertes apt-Repository
# unterhalb von _site/ und legt es so ab, wie GitHub Pages es ausliefert.
#
# Aufbau (Debian-Standard, nicht "flat"): dists/<kanal>/main/binary-amd64/.
# Damit kann eine Quelle zwei Kanäle führen – beta für die Testgeräte,
# stable für alle anderen – ohne zwei URLs.
#
# Aufruf:  tools/build-repo.sh [AUSGABEVERZEICHNIS]
# Signiert wird nur, wenn ein Schlüssel im Schlüsselbund liegt (in CI über
# GPG_PRIVATE_KEY importiert). Lokal ohne Schlüssel läuft alles bis auf die
# Signatur durch – so lässt sich der Index prüfen, ohne den privaten
# Schlüssel zu brauchen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/_site}"
ORIGIN="HomePilot OS"
CHANNELS="beta stable"
ARCH="amd64"
# Wie viele Versionen je Paket und Kanal bleiben liegen. Mehr als eine,
# weil das Update Center per apt auf eine ältere Version zurückrollen kann
# – dafür muss sie im Repository noch stehen.
KEEP="${KEEP:-3}"

command -v dpkg-scanpackages >/dev/null || { echo "dpkg-dev fehlt"; exit 1; }

# sha256/md5 heissen auf Linux und macOS verschieden. Der Index muss auf
# beiden entstehen koennen, sonst laesst er sich nur in CI pruefen.
if command -v sha256sum >/dev/null; then
    sha256() { sha256sum "$1" | awk '{print $1}'; }
    md5() { md5sum "$1" | awk '{print $1}'; }
else
    sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
    md5() { md5 -q "$1"; }
fi
filesize() { wc -c < "$1" | tr -d ' '; }

# write_release schreibt die Release-Datei von Hand.
#
# Bewusst ohne apt-ftparchive: das Paket apt-utils gibt es nur auf Debian,
# und damit waere der Index ausschliesslich in CI baubar gewesen – also
# genau dort ungeprueft, wo er entsteht. Das Format ist ueberschaubar, und
# an den Pruefsummen hier haengt die gesamte Verifikationskette.
write_release() {
    local dir="$1" channel="$2"
    {
        echo "Origin: $ORIGIN"
        echo "Label: $ORIGIN"
        echo "Suite: $channel"
        echo "Codename: $channel"
        echo "Architectures: $ARCH"
        echo "Components: main"
        echo "Description: HomePilot OS Update-Kanal ($channel)"
        echo "Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
        echo "Acquire-By-Hash: no"
        local f rel
        echo "MD5Sum:"
        for f in "$dir"/main/binary-"$ARCH"/Packages*; do
            rel="${f#$dir/}"
            printf " %s %16s %s\n" "$(md5 "$f")" "$(filesize "$f")" "$rel"
        done
        echo "SHA256:"
        for f in "$dir"/main/binary-"$ARCH"/Packages*; do
            rel="${f#$dir/}"
            printf " %s %16s %s\n" "$(sha256 "$f")" "$(filesize "$f")" "$rel"
        done
    } > "$dir/Release"
}

rm -rf "$OUT"
mkdir -p "$OUT"

# Alte Versionen wegräumen, bevor der Index entsteht: sonst wächst das
# Repository mit jedem RC um ~20 MB und die Indizes führen Pakete, die
# niemand mehr braucht.
prune_channel() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local names
    names="$(find "$dir" -name '*.deb' -exec dpkg-deb -f {} Package \; 2>/dev/null | sort -u)"
    for name in $names; do
        # Nach Version sortieren, nicht nach Dateinamen: "rc9" ist als Text
        # größer als "rc10", als Version aber kleiner.
        local sorted
        sorted="$(find "$dir" -name "${name}_*.deb" -exec sh -c \
            'printf "%s %s\n" "$(dpkg-deb -f "$1" Version)" "$1"' _ {} \; \
            | sort -k1,1 -V -r | awk '{print $2}')"
        local i=0
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            i=$((i + 1))
            if [ "$i" -gt "$KEEP" ]; then
                echo "    verwerfe alte Version: $(basename "$file")"
                rm -f "$file"
            fi
        done <<< "$sorted"
    done
}

for channel in $CHANNELS; do
    pool="$ROOT/pool/$channel"
    [ -d "$pool" ] || continue
    echo "==> Kanal $channel"
    prune_channel "$pool"

    mkdir -p "$OUT/pool/$channel" "$OUT/dists/$channel/main/binary-$ARCH"
    find "$pool" -name '*.deb' -exec cp {} "$OUT/pool/$channel/" \;

    # --multiversion: OHNE das nimmt dpkg-scanpackages je Paket nur die
    # hoechste Version in den Index auf. Die aelteren laegen zwar im Pool,
    # waeren fuer apt aber unsichtbar – und genau sie braucht das Update
    # Center fuer den Rollback auf eine vorherige Version.
    ( cd "$OUT" && dpkg-scanpackages --multiversion --arch "$ARCH" "pool/$channel" /dev/null ) \
        > "$OUT/dists/$channel/main/binary-$ARCH/Packages" 2>/dev/null
    gzip -9kf "$OUT/dists/$channel/main/binary-$ARCH/Packages"

    # Release mit den Prüfsummen aller Indexdateien. Dieselbe Datei wird
    # gleich signiert – daran hängt die ganze Verifikationskette.
    write_release "$OUT/dists/$channel" "$channel"

    # Signiert wird nur mit AUSDRUECKLICH benanntem Schluessel (GPG_KEY_ID).
    # Nicht mit "irgendeinem" aus dem Schluesselbund: lokal waere sonst
    # unbemerkt der persoenliche Schluessel des Entwicklers unter das
    # Repository geraten.
    if [ -n "${GPG_KEY_ID:-}" ]; then
        gpg_args=(--batch --yes --pinentry-mode loopback --local-user "$GPG_KEY_ID")
        [ -n "${GPG_PASSPHRASE:-}" ] && gpg_args+=(--passphrase "$GPG_PASSPHRASE")
        ( cd "$OUT/dists/$channel" \
            && gpg "${gpg_args[@]}" --clearsign -o InRelease Release \
            && gpg "${gpg_args[@]}" --detach-sign --armor -o Release.gpg Release )
        echo "    signiert mit $GPG_KEY_ID"
    else
        echo "    OHNE Signatur gebaut (GPG_KEY_ID nicht gesetzt)"
    fi

    echo "    $(grep -c '^Package:' "$OUT/dists/$channel/main/binary-$ARCH/Packages") Paket(e)"
done

cp "$ROOT/key.asc" "$OUT/key.asc"
cp "$ROOT/README.md" "$OUT/README.md" 2>/dev/null || true
# .nojekyll: ohne die Datei verschluckt GitHub Pages Verzeichnisse, deren
# Name mit einem Unterstrich beginnt – und ignoriert Dateien ohne Endung
# nicht immer zuverlässig.
touch "$OUT/.nojekyll"
echo "==> fertig in $OUT"

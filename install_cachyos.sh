#!/usr/bin/env bash
# Crowns-Helfer auf CachyOS (und anderen Arch-Systemen) installieren.
#
#   bash install_cachyos.sh
#
# Installiert Python und Qt fuer Python (python-pyqt6) ueber pacman, holt crowns-helfer.py (liegt die Datei neben
# diesem Skript, wird die genommen, sonst die aktuelle Version von GitHub) und richtet den Helfer ein: Symbol im
# Infobereich der Taskleiste, Autostart als systemd-Benutzerdienst crowns-helfer-tray.service.
set -euo pipefail

URL="https://github.com/NiklasM-foss/Crowns-Helfer/releases/latest/download/crowns-helfer.py"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "Bitte NICHT mit sudo starten, sondern als dein normaler Benutzer. Das Skript fragt selbst nach dem Passwort,"
    echo "wenn es Pakete installieren muss."
    exit 1
fi
if ! command -v pacman >/dev/null 2>&1; then
    echo "pacman nicht gefunden. Dieses Skript ist fuer CachyOS/Arch. Andere Systeme: python3 crowns-helfer.py"
    exit 1
fi

echo "== Pakete pruefen (python, python-pyqt6)"
fehlt=()
for p in python python-pyqt6; do
    pacman -Q "$p" >/dev/null 2>&1 || fehlt+=("$p")
done
if [ ${#fehlt[@]} -gt 0 ]; then
    echo "   installiere: ${fehlt[*]}"
    sudo pacman -S --needed --noconfirm "${fehlt[@]}"
else
    echo "   schon da"
fi

hier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$hier/crowns-helfer.py" ]; then
    quelle="$hier/crowns-helfer.py"
    echo "== crowns-helfer.py aus $hier"
else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    echo "== crowns-helfer.py von GitHub laden"
    curl -fsSL "$URL" -o "$tmp/crowns-helfer.py"
    quelle="$tmp/crowns-helfer.py"
fi

if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "Hinweis: keine grafische Sitzung gefunden (z.B. per SSH). Der Helfer laeuft dann als Timer ohne Symbol."
    echo "Fuer das Symbol das Skript einmal im Terminal der KDE-Sitzung starten."
fi

echo "== einrichten"
python3 "$quelle"

if systemctl --user is-enabled crowns-helfer-tray.service >/dev/null 2>&1; then
    echo
    echo "Fertig: Der Helfer sitzt in der Taskleiste (Infobereich, Krone) und startet mit jeder Anmeldung."
    echo "Status:     systemctl --user status crowns-helfer-tray.service"
    echo "Entfernen:  python3 ~/.local/share/crowns-helfer/crowns-helfer.py entfernen"
fi

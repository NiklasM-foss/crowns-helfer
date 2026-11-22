# Crowns-Helfer

Hält das Modpack von **Crowns & Cannons** bei allen Spielern automatisch auf dem Stand, den die Admins veröffentlicht
haben: Mods, Ressourcenpakete, Datenpakete, Shader, KubeJS und das nötige Java-Argument. Du musst keine Links mehr
anklicken und keine Mods mehr von Hand austauschen.

**Eigene Mods und Dateien, die du selbst hinzugefügt hast, werden nie angefasst.**

## Installation

Vorher einmal das Modpack ganz normal über die CurseForge-App installieren.

### Windows

1. [`Crowns-Helfer.bat`](https://github.com/NiklasM-foss/Crowns-Helfer/releases/latest) herunterladen.
2. Doppelklicken. Fragt Windows nach („Der Computer wurde durch Windows geschützt“), auf **Weitere Informationen** und
   dann **Trotzdem ausführen** klicken.
3. Fertig. Unten rechts in der Taskleiste (eventuell hinter dem Pfeil `^`) sitzt jetzt eine Krone. Der Helfer startet
   ab sofort mit Windows.

### CachyOS / Arch

1. [`install_cachyos.sh`](https://github.com/NiklasM-foss/Crowns-Helfer/releases/latest) herunterladen.
2. Im Terminal (als normaler Benutzer, nicht mit sudo): `bash install_cachyos.sh`
3. Das Skript installiert Python und Qt für Python, holt den Helfer und richtet ihn ein. Danach sitzt er im
   Infobereich der Taskleiste und startet als systemd-Benutzerdienst `crowns-helfer-tray.service` mit jeder Anmeldung.

### Andere Linux-Systeme

1. [`crowns-helfer.py`](https://github.com/NiklasM-foss/Crowns-Helfer/releases/latest) herunterladen.
2. Für das Symbol in der Taskleiste (KDE Plasma und andere) einmal Qt für Python installieren, zum Beispiel:
   - Debian, Ubuntu, Mint: `sudo apt install python3-pyqt6`
   - Fedora: `sudo dnf install python3-pyqt6`
3. `python3 crowns-helfer.py` ausführen. Der Helfer sitzt dann im Infobereich. Läuft die Sitzung über systemd (KDE
   Plasma, GNOME), startet er als Benutzerdienst `crowns-helfer-tray.service`, sonst über `~/.config/autostart`. Ohne
   Qt läuft er unsichtbar als systemd-Timer bzw. cron.

Erkannt werden CurseForge-Instanzen und unter Linux auch Prism-Launcher-Instanzen, deren Name mit „Crowns & Cannons“
beginnt.

## Bedienung

Rechtsklick auf die Krone:

| Menüpunkt | Was passiert |
|---|---|
| **Status anzeigen** (auch Doppelklick) | Pack-Version, letzter Abgleich, Ergebnis und Dateien, die du selbst herunterladen musst |
| **Jetzt aktualisieren** | sofort abgleichen |
| **Automatisch aktualisieren** | an/aus, gleicht alle 15 Minuten ab |
| **Mit Windows starten** bzw. **Mit dem System starten** | Autostart an/aus |
| **Protokoll öffnen** | zeigt, was der Helfer gemacht hat |
| **Beenden** | schließt den Helfer bis zum nächsten Start |

## Was der Helfer macht

- Er holt die aktuelle Pack-Liste der Admins und prüft jede Datei per Prüfsumme (SHA-512).
- Fehlt eine Datei oder ist sie veraltet, lädt er sie von der offiziellen Quelle: **Modrinth**, **CurseForge** (wenn
  der Autor das erlaubt) oder vom **Server** der Admins. Abgelegt wird nur, wenn die Prüfsumme stimmt.
- Alte Versionen derselben Mod entfernt er, aber nur Dateien, die das Pack früher selbst verteilt hat.
- Das Java-Argument `-Dorg.lwjgl.system.allocator=system` setzt er, sobald die CurseForge-App geschlossen ist (die App
  würde die Einstellung sonst beim Beenden überschreiben).
- Manche Mod-Autoren verbieten den Download durch Programme. Dann zeigt der Helfer dir den Link: Datei herunterladen,
  in deinem Downloads-Ordner liegen lassen, der Helfer legt sie automatisch an die richtige Stelle.

## Entfernen

- Windows: `Crowns-Helfer.bat entfernen` (zum Beispiel im Ordner der Datei in die Adresszeile `cmd` tippen und den
  Befehl eingeben).
- Linux: `python3 crowns-helfer.py entfernen`

Der Helfer, sein Autostart und seine eigenen Dateien werden gelöscht. Die Dateien in deinen Instanzen bleiben, wie
sie sind.

## Protokoll

- Windows: `%LOCALAPPDATA%\CrownsHelfer\helfer.log`
- Linux: `~/.local/share/crowns-helfer/helfer.log`

## Für Admins

Das Pack wird auf der Admin-Seite `https://editor.niklasmetzger.de/pack/admin/` gepflegt: Instanz-Ordner wählen,
prüfen, veröffentlichen. Der Server-Teil liegt im Repository
[Crowns-and-Cannons-Core](https://github.com/NiklasM-foss/Crowns-and-Cannons-Core) (Ordner `editor/`).

## Lizenz

GNU Lesser General Public License, Version 3 (LGPL-3.0-only), siehe `COPYING.LESSER` und `COPYING`.

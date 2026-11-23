# Changelog

## 1.1.0

- Der Helfer aktualisiert sich selbst: neuestes Release auf GitHub, Prüfung per SHA-256, die Taskleisten-App startet
  danach mit der neuen Version neu (Windows und Linux).
- Linux: findet CurseForge-Instanzen auch im eingedeutschten Dokumente-Ordner (`xdg-user-dir DOCUMENTS`, `~/Dokumente`).
- Windows: Taskleisten-App startet auch, wenn die vorige Instanz hart beendet wurde.

## 1.0.0

- Erste Version: hält das Crowns-&-Cannons-Modpack automatisch aktuell (Mods, Ressourcenpakete, Datenpakete, Shader,
  KubeJS, Java-Argument), Quellen Modrinth, CurseForge und der Server der Admins, Prüfung per SHA-512.
- Symbol im Infobereich der Taskleiste unter Windows und KDE/Linux (Qt) mit Status, Jetzt aktualisieren, automatischen
  Updates und Autostart an/aus.
- Dateien, die nicht automatisch geladen werden dürfen: Link im Statusfenster, Übernahme aus dem Downloads-Ordner.
- Linux: Autostart der Taskleisten-App als systemd-Benutzerdienst (neu gestartet nach Absturz), `install_cachyos.sh`
  für CachyOS/Arch.
- Eigene Dateien der Spieler werden nie angefasst.

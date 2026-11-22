#!/usr/bin/env python3
"""Crowns & Cannons Helfer für Linux.

Hält das ganze Modpack automatisch aktuell: Mods, Ressourcenpakete, Datenpakete, Shader, KubeJS und das
Java-Argument. Quellen: Modrinth, CurseForge oder der Pi. Dateien, die niemand automatisch laden darf, holt der
Helfer aus dem Downloads-Ordner, sobald der Spieler sie dort hat. Eigene Dateien werden nie angefasst.
Gleiche Logik wie Crowns-Helfer.bat unter Windows.

  python3 crowns-helfer.py            einrichten (Symbol in der Taskleiste mit Qt, sonst systemd-Timer/cron), einmal abgleichen
  python3 crowns-helfer.py tray       Taskleisten-App starten (KDE Plasma u.a., braucht PyQt6/PySide6/PyQt5)
  python3 crowns-helfer.py auto       nur abgleichen (so ruft der Timer ihn auf)
  python3 crowns-helfer.py entfernen  Timer und Dateien wieder löschen

Unterstützt CurseForge-Instanzen (minecraftinstance.json) und Prism-Launcher-Instanzen (instance.cfg).
Braucht nur Python 3, keine Zusatzpakete.
"""
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

QUELLE = os.environ.get("CROWNS_HELFER_QUELLE", "https://editor.niklasmetzger.de/pack/crowns.json")
HOME = Path.home()
ORDNER = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "crowns-helfer"
LOG = ORDNER / "helfer.log"
UA = {"User-Agent": "crowns-helfer/1.0.0"}
ERLAUBT = re.compile(r"^(mods|resourcepacks|datapacks|shaderpacks|kubejs)/")
DOWNLOADS = Path(os.environ.get("CROWNS_HELFER_DOWNLOADS", "") or (HOME / "Downloads"))
AUTO = len(sys.argv) > 1 and sys.argv[1] in ("auto", "tray")
TEST_WURZEL = os.environ.get("CROWNS_HELFER_WURZEL", "")


def schreib(text):
    ORDNER.mkdir(parents=True, exist_ok=True)
    if not AUTO:
        print(text)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S") + "  " + text + "\n")


def einrichten():
    ORDNER.mkdir(parents=True, exist_ok=True)
    ziel = ORDNER / "crowns-helfer.py"
    if Path(__file__).resolve() != ziel:
        shutil.copy2(__file__, ziel)
    py = sys.executable or "python3"
    if qt() and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        # Taskleisten-App statt Timer: alte Timer entfernen, Autostart eintragen, App starten
        timer_entfernen()
        e = einst()
        einst_speichern(e)
        autostart(bool(e.get("autostart", True)))
        tray_laeuft_stoppen()
        subprocess.Popen([py, str(ziel), "tray"], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("Eingerichtet: Der Helfer sitzt jetzt in der Taskleiste (Infobereich, Krone). Rechtsklick: Status,")
        print("Jetzt aktualisieren, automatische Updates und Autostart an/aus, Beenden.")
        return True
    print("Hinweis: Für das Symbol in der Taskleiste fehlt Qt für Python. Installieren mit: " + qt_hinweis())
    print("Bis dahin läuft der Helfer als Timer im Hintergrund.")
    systemd = HOME / ".config/systemd/user"
    if shutil.which("systemctl"):
        systemd.mkdir(parents=True, exist_ok=True)
        (systemd / "crowns-helfer.service").write_text(
            "[Unit]\nDescription=Crowns & Cannons Helfer\n\n[Service]\nType=oneshot\n"
            f"ExecStart={py} {ziel} auto\n", encoding="utf-8")
        (systemd / "crowns-helfer.timer").write_text(
            "[Unit]\nDescription=Crowns & Cannons Helfer alle 15 Minuten\n\n[Timer]\nOnBootSec=1min\nOnUnitActiveSec=15min\n"
            "Persistent=true\n\n[Install]\nWantedBy=timers.target\n", encoding="utf-8")
        r = subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True, text=True)
        r = subprocess.run(["systemctl", "--user", "enable", "--now", "crowns-helfer.timer"], capture_output=True, text=True)
        if r.returncode == 0:
            print("Eingerichtet: systemd-Timer, läuft nach dem Start und alle 15 Minuten.")
            return
        print("systemd-Timer ging nicht (" + r.stderr.strip() + "), versuche cron.")
    if shutil.which("crontab"):
        alt = subprocess.run(["crontab", "-l"], capture_output=True, text=True).stdout
        zeilen = [z for z in alt.splitlines() if "crowns-helfer.py" not in z]
        zeilen.append(f"*/15 * * * * {py} {ziel} auto >/dev/null 2>&1")
        zeilen.append(f"@reboot {py} {ziel} auto >/dev/null 2>&1")
        subprocess.run(["crontab", "-"], input="\n".join(zeilen) + "\n", text=True)
        print("Eingerichtet: cron, alle 15 Minuten und nach dem Start.")
    else:
        print("Weder systemd noch cron gefunden. Bitte crowns-helfer.py auto vor dem Spielen selbst starten.")


def timer_entfernen():
    if shutil.which("systemctl"):
        subprocess.run(["systemctl", "--user", "disable", "--now", "crowns-helfer.timer"], capture_output=True)
        for n in ("crowns-helfer.service", "crowns-helfer.timer"):
            (HOME / ".config/systemd/user" / n).unlink(missing_ok=True)
        subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
    if shutil.which("crontab"):
        alt = subprocess.run(["crontab", "-l"], capture_output=True, text=True).stdout
        if "crowns-helfer.py" in alt:
            subprocess.run(["crontab", "-"], input="\n".join(z for z in alt.splitlines() if "crowns-helfer.py" not in z) + "\n", text=True)


def entfernen():
    tray_laeuft_stoppen()
    autostart(False)
    if shutil.which("systemctl"):
        subprocess.run(["systemctl", "--user", "disable", "--now", "crowns-helfer.timer"], capture_output=True)
        for n in ("crowns-helfer.service", "crowns-helfer.timer"):
            (HOME / ".config/systemd/user" / n).unlink(missing_ok=True)
        subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
    if shutil.which("crontab"):
        alt = subprocess.run(["crontab", "-l"], capture_output=True, text=True).stdout
        subprocess.run(["crontab", "-"], input="\n".join(z for z in alt.splitlines() if "crowns-helfer.py" not in z) + "\n", text=True)
    shutil.rmtree(ORDNER, ignore_errors=True)
    print("Crowns-Helfer ist entfernt. Die Dateien in deinen Instanzen bleiben, wie sie sind.")


def liste():
    cache = ORDNER / "crowns.json"
    try:
        if re.match(r"^https?://", QUELLE):
            with urllib.request.urlopen(urllib.request.Request(QUELLE, headers=UA), timeout=20) as r:
                roh = r.read().decode("utf-8")
        else:
            roh = Path(QUELLE).read_text(encoding="utf-8")
        pack = json.loads(roh)
        ORDNER.mkdir(parents=True, exist_ok=True)
        cache.write_text(roh, encoding="utf-8")
        return pack
    except Exception as e:
        if cache.exists():
            schreib(f"Liste nicht erreichbar, nehme die zuletzt geladene ({e})")
            return json.loads(cache.read_text(encoding="utf-8"))
        schreib(f"Liste nicht erreichbar und noch keine gespeichert: {e}")
        return None


def wurzeln():
    if TEST_WURZEL:
        return [Path(TEST_WURZEL)]
    w = []
    storage = HOME / ".config/CurseForge/storage.json"
    try:
        s = json.loads(storage.read_text(encoding="utf-8"))
        mc = json.loads(s.get("minecraft-settings", "{}"))
        if mc.get("minecraftRoot"):
            w += [Path(mc["minecraftRoot"]) / "Instances", Path(mc["minecraftRoot"]) / "minecraft/Instances"]
    except Exception:
        pass
    w += [HOME / "curseforge/minecraft/Instances", HOME / "Documents/curseforge/minecraft/Instances",
          HOME / ".local/share/PrismLauncher/instances", HOME / ".var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances",
          HOME / ".local/share/multimc/instances"]
    return list(dict.fromkeys(w))


def instanzen(pack):
    gefunden = []
    for r in wurzeln():
        if not r.is_dir():
            continue
        for d in sorted(p for p in r.iterdir() if p.is_dir()):
            cf, prism = d / "minecraftinstance.json", d / "instance.cfg"
            name = d.name
            if cf.exists():
                try:
                    name = json.loads(cf.read_text(encoding="utf-8-sig")).get("name") or name
                except Exception:
                    pass
                art, mods = "cf", d / "mods"
            elif prism.exists():
                m = re.search(r"^name=(.*)$", prism.read_text(encoding="utf-8", errors="replace"), re.M)
                name = m.group(1).strip() if m else name
                mc = d / ".minecraft" if (d / ".minecraft").exists() else d / "minecraft"
                art, mods = "prism", mc / "mods"
            else:
                continue
            if any(name.startswith(p) or d.name.startswith(p) for p in pack.get("instanzen", [])):
                gefunden.append((art, d, name, mods))
    return gefunden


def sha512(p):
    h = hashlib.sha512()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def pfad_ok(p):
    return bool(ERLAUBT.match(p)) and ".." not in p.split("/") and ":" not in p and "\\" not in p and len(p) < 300


def aus_downloads(d):
    if not DOWNLOADS.is_dir():
        return None
    for f in DOWNLOADS.iterdir():
        try:
            if f.is_file() and (not d.get("groesse") or f.stat().st_size == int(d["groesse"])) and sha512(f) == d["sha512"].lower():
                return f
        except OSError:
            continue
    return None


def dateien_abgleichen(pack, ordner, basis, manuell):
    neu = weg = 0
    for d in pack.get("dateien", []):
        if not pfad_ok(d.get("pfad", "")):
            continue
        ziel = ordner / d["pfad"]
        ok = ziel.exists() and sha512(ziel) == d["sha512"].lower()
        if not ok:
            ziel.parent.mkdir(parents=True, exist_ok=True)
            tmp = ORDNER / "download.tmp"
            for q in d.get("quellen", []):
                url = basis + q if q.startswith("/") else q
                try:
                    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r, open(tmp, "wb") as f:
                        shutil.copyfileobj(r, f)
                    if sha512(tmp) != d["sha512"].lower():
                        raise ValueError("Prüfsumme stimmt nicht")
                    shutil.move(str(tmp), str(ziel))
                    ok = True
                    neu += 1
                    schreib("  neu: " + d["pfad"])
                    break
                except Exception as e:
                    tmp.unlink(missing_ok=True)
                    schreib(f"  {d['pfad']}: Quelle fehlgeschlagen ({e})")
            if not ok:
                dl = aus_downloads(d)
                if dl:
                    shutil.move(str(dl), str(ziel))
                    ok = True
                    neu += 1
                    schreib("  aus Downloads übernommen: " + d["pfad"])
                else:
                    manuell[d["sha512"]] = d
        if ok:
            for a in d.get("alt", []):
                if pfad_ok(a) and a != d["pfad"] and (ordner / a).exists():
                    try:
                        (ordner / a).unlink()
                        weg += 1
                        schreib("  alte Version entfernt: " + a)
                    except OSError:
                        schreib(f"  {a} ist gerade gesperrt, nächster Versuch später")
    schreib(f"  {neu} neu, {weg} entfernt")
    return neu, weg


def hinweis_manuell(manuell):
    """Dateien, die man selbst herunterladen muss: Hinweis mit Links (höchstens alle 6 Stunden im Hintergrund)."""
    if not manuell:
        return
    stand = ORDNER / "hinweis.json"
    try:
        zuletzt = json.loads(stand.read_text()).get("zeit", 0)
    except Exception:
        zuletzt = 0
    if AUTO and time.time() - zuletzt < 6 * 3600:
        return
    stand.write_text(json.dumps({"zeit": time.time()}))
    zeilen = [f"{d.get('name') or d['pfad']}: {d.get('seite') or 'keine Seite angegeben'}" for d in manuell.values()]
    text = ("Diese Dateien darf der Helfer nicht selbst laden. Bitte herunterladen (in " + str(DOWNLOADS)
            + "), der Helfer legt sie beim nächsten Lauf an die richtige Stelle:\n" + "\n".join(zeilen))
    schreib(text)
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "Crowns-Helfer", "Crowns & Cannons: bitte herunterladen", text], capture_output=True)
    if not AUTO and shutil.which("xdg-open"):
        for d in manuell.values():
            if d.get("seite"):
                subprocess.run(["xdg-open", d["seite"]], capture_output=True)


def cf_laeuft():
    if os.environ.get("CROWNS_HELFER_TEST"):
        return False
    r = subprocess.run(["pgrep", "-i", "-f", "curseforge"], capture_output=True, text=True)
    return r.returncode == 0 and any(pid != str(os.getpid()) for pid in r.stdout.split())


def jvm_cf(pack, datei):
    raw = datei.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    alt = json.loads(text).get("javaArgsOverride") or ""
    fehlt = [a for a in pack.get("jvm", []) if a not in alt.split()]
    if not fehlt:
        schreib("  Java-Argument: gesetzt")
        return
    if cf_laeuft():
        schreib("  Java-Argument fehlt, CurseForge ist offen: wird gesetzt, sobald die App geschlossen ist")
        return "offen"
    neu = (alt.strip() + " " + " ".join(fehlt)).strip()
    wert = '"javaArgsOverride": ' + json.dumps(neu)
    rx = re.compile(r'"javaArgsOverride"\s*:\s*(null|"(?:[^"\\]|\\.)*")')
    text2 = rx.sub(lambda _: wert, text, count=1) if rx.search(text) else re.sub(r"^\s*\{", "{\n  " + wert + ",", text, count=1)
    json.loads(text2)  # nichts Kaputtes schreiben
    shutil.copy2(datei, str(datei) + ".bak")
    datei.write_bytes((b"\xef\xbb\xbf" if bom else b"") + text2.encode("utf-8"))
    schreib("  Java-Argument gesetzt: " + neu)


def jvm_prism(pack, cfg):
    text = cfg.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^JvmArgs=(.*)$", text, re.M)
    alt = m.group(1).strip() if m else ""
    fehlt = [a for a in pack.get("jvm", []) if a not in alt.split()]
    if not fehlt and re.search(r"^OverrideJavaArgs=true$", text, re.M):
        schreib("  Java-Argument: gesetzt")
        return
    neu = (alt + " " + " ".join(fehlt)).strip()
    text = re.sub(r"^JvmArgs=.*$", "JvmArgs=" + neu.replace("\\", "\\\\"), text, flags=re.M) if m else text.rstrip("\n") + "\nJvmArgs=" + neu + "\n"
    if re.search(r"^OverrideJavaArgs=", text, re.M):
        text = re.sub(r"^OverrideJavaArgs=.*$", "OverrideJavaArgs=true", text, flags=re.M)
    else:
        text = text.rstrip("\n") + "\nOverrideJavaArgs=true\n"
    shutil.copy2(cfg, str(cfg) + ".bak")
    cfg.write_text(text, encoding="utf-8")
    schreib("  Java-Argument gesetzt (Prism): " + neu)


def abgleichen():
    pack = liste()
    if not pack:
        return
    gefunden = instanzen(pack)
    if not gefunden:
        schreib("Keine Crowns-&-Cannons-Instanz gefunden.")
        return
    m = re.match(r"^(https?://[^/]+)", QUELLE)
    basis = m.group(1) if m else ""
    manuell = {}
    status_inst = []
    for art, d, name, mods in gefunden:
        schreib(f"Instanz: {name} ({'CurseForge' if art == 'cf' else 'Prism'}, Pack-Version {pack.get('version')})")
        neu, weg = dateien_abgleichen(pack, mods.parent, basis, manuell)
        si = {"name": name, "neu": neu, "weg": weg, "jvmOffen": False}
        status_inst.append(si)
        if not pack.get("jvm"):
            continue
        try:
            if art == "cf":
                si["jvmOffen"] = jvm_cf(pack, d / "minecraftinstance.json") == "offen"
            else:
                jvm_prism(pack, d / "instance.cfg")
        except Exception as e:
            schreib(f"  Java-Argument nicht gesetzt: {e}")
    try:
        (ORDNER / "status.json").write_text(json.dumps({
            "zeit": time.strftime("%d.%m.%Y %H:%M"), "packVersion": pack.get("version"), "instanzen": status_inst, "fehler": "",
            "manuell": [{"name": x.get("name") or x["pfad"], "seite": x.get("seite", ""), "ordner": x["pfad"].split("/")[0]} for x in manuell.values()]},
            ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass
    # Mit Taskleisten-App zeigt die App die Hinweise, sonst eine Benachrichtigung
    if not os.environ.get("CROWNS_HELFER_TEST") and not (ORDNER / "einstellungen.json").exists():
        hinweis_manuell(manuell)
    try:
        z = LOG.read_text(encoding="utf-8").splitlines()
        if len(z) > 800:
            LOG.write_text("\n".join(z[-400:]) + "\n", encoding="utf-8")
    except Exception:
        pass


# ---- Taskleisten-App (KDE Plasma und andere Desktops mit Infobereich, über Qt) ----

EINST = ORDNER / "einstellungen.json"
STATUS = ORDNER / "status.json"
AUTOSTART = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "autostart" / "crowns-helfer.desktop"
ICON = "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"


def qt():
    """Qt-Bindings für Python suchen (KDE nutzt Qt). None, wenn keine da sind."""
    import importlib
    for mod in ("PyQt6", "PySide6", "PyQt5", "PySide2"):
        try:
            return (mod, importlib.import_module(mod + ".QtWidgets"), importlib.import_module(mod + ".QtGui"),
                    importlib.import_module(mod + ".QtCore"))
        except ImportError:
            continue
    return None


def qt_hinweis():
    if shutil.which("pacman"):
        return "sudo pacman -S python-pyqt6"
    if shutil.which("apt"):
        return "sudo apt install python3-pyqt6   (ältere Systeme: python3-pyqt5)"
    if shutil.which("dnf"):
        return "sudo dnf install python3-pyqt6"
    if shutil.which("zypper"):
        return "sudo zypper install python3-PyQt6"
    return "Qt für Python (PyQt6) über die Paketverwaltung installieren"


def einst():
    try:
        return json.loads(EINST.read_text(encoding="utf-8"))
    except Exception:
        return {"autoUpdate": True, "autostart": True}


def einst_speichern(e):
    ORDNER.mkdir(parents=True, exist_ok=True)
    EINST.write_text(json.dumps(e), encoding="utf-8")


def autostart(an):
    ziel = ORDNER / "crowns-helfer.py"
    if an:
        AUTOSTART.parent.mkdir(parents=True, exist_ok=True)
        AUTOSTART.write_text("[Desktop Entry]\nType=Application\nName=Crowns & Cannons Helfer\n"
                             f"Exec={sys.executable or 'python3'} {ziel} tray\nX-GNOME-Autostart-enabled=true\n", encoding="utf-8")
    else:
        AUTOSTART.unlink(missing_ok=True)


def tray_laeuft_stoppen():
    if shutil.which("pkill"):
        subprocess.run(["pkill", "-f", "crowns-helfer.py tray"], capture_output=True)


def tray():
    q = qt()
    if not q:
        print("Für das Symbol in der Taskleiste fehlt Qt für Python: " + qt_hinweis())
        return
    mod, W, G, C = q
    QAction = getattr(G, "QAction", None) or getattr(W, "QAction")
    app = W.QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("Crowns-Helfer")
    pm = G.QPixmap()
    pm.loadFromData(__import__("base64").b64decode(ICON))
    icon = G.QIcon(pm)
    if not W.QSystemTrayIcon.isSystemTrayAvailable():
        print("Kein Infobereich (System Tray) gefunden. Bei GNOME braucht es die Erweiterung AppIndicator.")
    ti = W.QSystemTrayIcon(icon)
    ti.setToolTip("Crowns & Cannons Helfer")
    zustand = {"proc": None, "manuell": "", "cf": cf_laeuft(), "fenster": None}
    skript = str(ORDNER / "crowns-helfer.py") if (ORDNER / "crowns-helfer.py").exists() else str(Path(__file__).resolve())

    def status():
        try:
            return json.loads(STATUS.read_text(encoding="utf-8"))
        except Exception:
            return None

    def abgleich():
        p = zustand["proc"]
        nicht_laufend = getattr(getattr(C.QProcess, "ProcessState", C.QProcess), "NotRunning")
        if p is not None and p.state() != nicht_laufend:
            return
        p = C.QProcess()
        p.finished.connect(fertig)
        p.start(sys.executable or "python3", [skript, "auto"])
        zustand["proc"] = p
        ti.setToolTip("Crowns & Cannons Helfer: aktualisiert ...")
        a_jetzt.setEnabled(False)

    def fertig(*_):
        a_jetzt.setEnabled(True)
        s = status()
        if not s:
            return
        n = sum(int(i.get("neu", 0)) for i in s.get("instanzen", []))
        m = s.get("manuell", [])
        ti.setToolTip("Crowns & Cannons Helfer: Pack %s, %s" % (s.get("packVersion"), ("%d Datei(en) selbst laden" % len(m)) if m else "aktuell"))
        if n:
            ti.showMessage("Crowns & Cannons", "%d Datei(en) aktualisiert." % n, icon, 5000)
        sig = ",".join(x.get("name", "") for x in m)
        if sig and sig != zustand["manuell"]:
            ti.showMessage("Crowns & Cannons", "Bitte Dateien selbst herunterladen. Klick hier für die Links.", icon, 8000)
        zustand["manuell"] = sig

    def fenster():
        s = status()
        e = einst()
        zeilen = []
        if not s:
            zeilen.append("<b>Noch kein Abgleich gelaufen.</b>")
        else:
            zeilen.append("<b>Pack-Version %s, letzter Abgleich %s</b>" % (s.get("packVersion"), s.get("zeit")))
            for i in s.get("instanzen", []):
                zeilen.append("&nbsp;&nbsp;%s: %s neu, %s entfernt%s" % (i.get("name"), i.get("neu"), i.get("weg"),
                                                                       ", Java-Argument wartet (CurseForge schließen)" if i.get("jvmOffen") else ""))
            if s.get("manuell"):
                zeilen.append("<br><b>Bitte selbst herunterladen</b> (der Helfer legt die Datei dann automatisch ab):")
                for m in s["manuell"]:
                    zeilen.append('&nbsp;&nbsp;<a href="%s">%s</a> (%s)' % (m.get("seite") or "#", m.get("name"), m.get("ordner")))
            else:
                zeilen.append("Alles aktuell.")
        zeilen.append("<br>Automatische Updates: %s, Autostart: %s" % ("an (alle 15 Minuten)" if e.get("autoUpdate") else "aus",
                                                                       "an" if e.get("autostart") else "aus"))
        d = W.QDialog()
        d.setWindowTitle("Crowns & Cannons Helfer")
        d.setWindowIcon(icon)
        lay = W.QVBoxLayout(d)
        lab = W.QLabel("<br>".join(zeilen))
        lab.setOpenExternalLinks(True)
        lab.setTextFormat(C.Qt.TextFormat.RichText if hasattr(C.Qt, "TextFormat") else C.Qt.RichText)
        lay.addWidget(lab)
        reihe = W.QHBoxLayout()
        b1 = W.QPushButton("Jetzt aktualisieren")
        b1.clicked.connect(lambda: (abgleich(), d.close()))
        b2 = W.QPushButton("Protokoll")
        b2.clicked.connect(lambda: subprocess.Popen(["xdg-open", str(LOG)]))
        b3 = W.QPushButton("Schließen")
        b3.clicked.connect(d.close)
        for b in (b1, b2, b3):
            reihe.addWidget(b)
        lay.addLayout(reihe)
        zustand["fenster"] = d
        d.show()
        d.raise_()

    menu = W.QMenu()
    a_status = QAction("Status anzeigen")
    f = a_status.font()
    f.setBold(True)
    a_status.setFont(f)
    a_jetzt = QAction("Jetzt aktualisieren")
    a_auto = QAction("Automatisch aktualisieren")
    a_auto.setCheckable(True)
    a_start = QAction("Mit dem System starten")
    a_start.setCheckable(True)
    a_log = QAction("Protokoll öffnen")
    a_ende = QAction("Beenden")
    e0 = einst()
    a_auto.setChecked(bool(e0.get("autoUpdate", True)))
    a_start.setChecked(bool(e0.get("autostart", True)))
    for a in (a_status, a_jetzt):
        menu.addAction(a)
    menu.addSeparator()
    menu.addAction(a_auto)
    menu.addAction(a_start)
    menu.addSeparator()
    menu.addAction(a_log)
    menu.addAction(a_ende)
    ti.setContextMenu(menu)

    def auto_umschalten(an):
        e = einst()
        e["autoUpdate"] = bool(an)
        einst_speichern(e)
        if an:
            abgleich()

    def start_umschalten(an):
        e = einst()
        e["autostart"] = bool(an)
        einst_speichern(e)
        autostart(bool(an))

    a_status.triggered.connect(fenster)
    a_jetzt.triggered.connect(abgleich)
    a_auto.toggled.connect(auto_umschalten)
    a_start.toggled.connect(start_umschalten)
    a_log.triggered.connect(lambda: subprocess.Popen(["xdg-open", str(LOG)]))
    a_ende.triggered.connect(app.quit)
    ti.messageClicked.connect(fenster)

    def aktiviert(grund):
        if grund in (getattr(W.QSystemTrayIcon, "DoubleClick", None), getattr(getattr(W.QSystemTrayIcon, "ActivationReason", object), "DoubleClick", None),
                     getattr(W.QSystemTrayIcon, "Trigger", None), getattr(getattr(W.QSystemTrayIcon, "ActivationReason", object), "Trigger", None)):
            fenster()
    ti.activated.connect(aktiviert)

    # Downloads beobachten: neue Datei und etwas war von Hand zu holen -> sofort abgleichen
    beob = C.QFileSystemWatcher()
    if DOWNLOADS.is_dir():
        beob.addPath(str(DOWNLOADS))
    beob.directoryChanged.connect(lambda _p: zustand["manuell"] and abgleich())

    def takt():
        if a_auto.isChecked():
            abgleich()

    t = C.QTimer()
    t.timeout.connect(takt)
    t.start(15 * 60 * 1000)
    w = C.QTimer()
    w.timeout.connect(lambda: _cf_pruefen())

    def _cf_pruefen():
        cf = cf_laeuft()
        if zustand["cf"] and not cf:
            s = status()
            if s and any(i.get("jvmOffen") for i in s.get("instanzen", [])):
                abgleich()
        zustand["cf"] = cf
    w.start(20 * 1000)

    ti.show()
    C.QTimer.singleShot(3000, lambda: a_auto.isChecked() and abgleich())
    fertig()
    sys.exit(app.exec() if hasattr(app, "exec") else app.exec_())


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "entfernen":
        entfernen()
    elif len(sys.argv) > 1 and sys.argv[1] == "tray":
        tray()
    else:
        if not AUTO:
            print("\nCrowns & Cannons Helfer\nHält das Modpack automatisch aktuell (Mods, Ressourcenpakete, Datenpakete, Shader, KubeJS, Java-Argument).\n"
                  "Eigene Dateien werden nie angefasst.\n")
            if not TEST_WURZEL and einrichten():
                sys.exit(0)  # die Taskleisten-App gleicht selbst ab
            print()
        abgleichen()
        if not AUTO:
            print("\nFertig. Protokoll:", LOG)

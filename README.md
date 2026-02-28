## 1. Vorbereitung: Git installieren
Bevor du das Terminal nutzen kannst, muss Git auf deinem System installiert sein.

    1. Lade Git for Windows herunter: git-scm.com.

    2. Installiere es mit den Standardeinstellungen.

    3. Öffne dein Terminal (Suche nach cmd oder PowerShell im Startmenü).

    4. Prüfe die Installation mit: git --version. Wenn eine Versionsnummer erscheint, ist alles bereit.

## 2. Identität festlegen
Git muss wissen, wer die Änderungen hochlädt. Gib folgende Befehle im Terminal ein:

`
git config --global user.name "Dein Name"
`

`
git config --global user.email "deine-email@beispiel.de" (Die Mail deines GitHub-Accounts).
`
## 3. Repository auf GitHub erstellen
Bevor wir Dateien hochladen, brauchen wir einen "Container" auf GitHub.

Logge dich auf GitHub.com ein.

Klicke oben rechts auf das + und wähle New repository.

Gib dem Repository einen Namen (z. B. mein-dcs-projekt).

Lass die Optionen "README", ".gitignore" und "License" deaktiviert (das fügen wir später hinzu).

Klicke auf Create repository.

Wichtig: Kopiere dir die URL, die jetzt angezeigt wird (sie endet auf .git).

## 4. Das lokale Projekt vorbereiten
Jetzt verbinden wir deinen Ordner mit Git.

**Navigiere im Terminal in deinen Projektordner:**
cd "C:\Pfad\zu\deinem\Projekt"

- **Git initialisieren:**
`
git init (Das erstellt einen versteckten .git Ordner).
`
- **Dateien hinzufügen:**
`
git add . (Der Punkt bedeutet: "Nimm alle Dateien in diesem Ordner").
`
# **Erster Speicherpunkt (Commit):**
`
git commit -m "Erster Upload meines Projekts"
`
## 5. Projekt zu GitHub hochladen (Push)
Nun verknüpfen wir deinen PC mit dem Online-Speicherplatz.

- **Haupt-Branch festlegen:**
`
git branch -M main
`
- **Remote-Ziel hinzufügen:**
`
git remote add origin https://github.com/DEIN-NUTZERNAME/DEIN-REPO.git (Hier die kopierte URL einfügen).
`
- **Hochladen:**
`
git push -u origin main
`
Hinweis: Windows wird dich nun wahrscheinlich nach einem Login fragen. Ein Browserfenster öffnet sich, in dem du GitHub den Zugriff erlaubst. Das musst du nur einmal machen.


# Zusammenfassung der Befehle
Wenn du in Zukunft Änderungen an deinen Skripten machst, ist der Ablauf immer dieser "Dreisatz":

**git add .**(Änderungen vormerken)

**git commit -m "Beschreibung der Änderung"** (Änderungen lokal speichern)

**git push** (Änderungen online hochladen)

Möchtest du als Nächstes wissen, wie du eine .gitignore Datei erstellst, damit Git nicht versehentlich unnötigen Datenmüll von deinem Server oder DCS mit hochlädt?
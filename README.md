# Posture

iOS-App, die über die Bewegungssensoren der AirPods die Kopf- und Rückenhaltung am Schreibtisch trackt. Das iPhone bleibt gesperrt; der Coach ("Theo") meldet sich nur bei echtem Zusammensacken.

## Bauen

Voraussetzungen: macOS mit Xcode 16 oder neuer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Posture.xcodeproj
```

In Xcode unter *Signing & Capabilities* das eigene Team wählen und den Bundle Identifier (`com.example.posture`) anpassen.

- **Echtes Gerät**: nötig für AirPods-Motion (AirPods Pro, AirPods 3 oder neuer, AirPods Max, Beats Fit Pro).
- **Simulator**: spielt eine geskriptete Schreibtisch-Szene ab (aufrecht, Blick auf Notizen, langsames Einsacken, Aufrichten), damit Live-Screen, Orb und Journal ohne AirPods sichtbar sind.
- **Beispieldaten**: im Debug-Build unter Profil > Developer > "Load a sample week".

Ohne Mac: Repository zu GitHub pushen, `.github/workflows/ci.yml` baut die App und führt die Tests auf einem macOS-Runner aus.

## Aufbau

```
Posture/
  App/            PostureApp, AppModel (Verdrahtung + Auto-Start), RootView, Tab-Bar
  Core/
    Posture/      PostureEngine (Heuristik), FatigueMonitor, Calibrator, SyntheticHead  – reines Swift, testbar
    Motion/       HeadphoneMotionService (CMHeadphoneMotionManager), PhoneContextService (Handy in Benutzung?)
    Guard/        LocationAndPowerGuard (Geofences, Stromsparmodus, Akku), AutoStartPolicy (reine Regel)
    Audio/        AudioCoachService (Hintergrund-Audio, Chimes, Stimme), CoachVoice (Stimmenauswahl), CoachScript (Texte en/de)
    Session/      SessionManager, LiveActivityController (Karte auf dem Sperrbildschirm), SessionStore (Journal als JSON), SettingsStore, Notifier
  Models/         SessionRecord, DaySummary, UserSettings
  Design/         Theme, Komponenten, SpineOrbView, Charts, Illustrationen
  Features/       Home, Live, Insights, Tracker, Social, Onboarding, Reset, Profile
PostureWidgets/   Widget-Extension: zeichnet die Live Activity (Sperrbildschirm, Dynamic Island)
Shared/           PostureActivityAttributes, von App und Extension gemeinsam kompiliert
PostureTests/     Szenario-Tests der Heuristik, Auto-Start-Regel, FatigueMonitor
```

## Wie die Haltungserkennung funktioniert

Alle Schwellen stehen in `Core/Posture/PostureTuning.swift`.

1. **Nur Schwerkraft, kein Yaw.** Gemessen wird der Schwerkraftvektor im Kopfhörer-Koordinatensystem relativ zur kalibrierten Baseline. Stuhldrehen verändert ihn nicht.
2. **Leichte Vorneigung zum Bildschirm ist normal.** Die Baseline ist "aufrecht, Blick geradeaus". Am Monitor oder Laptop kippt der Kopf ein paar Grad nach vorn; die ersten 6° Vorneigung (`screenLean`) zählen deshalb gar nicht. Erst danach beginnen die Bänder: gut bis 14°, Slouch ab 22° Vorneigung.
3. **Wie der Kopf den guten Bereich verlässt, zählt mehr als der Winkel.** Schnelles Nicken (über 25°/s) ohne Absinken des Kopfes = bewusster Blick nach unten, bekommt eine lange Leine. Langsames Driften (unter 8°/s) = Einsacken. Schnelles Kippen mit Absinken = Zusammenfallen.
4. **Slouch-Load statt Timer.** Ein undichter Integrator füllt sich je nach Schwere und Kontext und leert sich bei guter Haltung. Kurze Ausreißer (Trinken, Blick zur Seite) füllen ihn nie, wiederholte addieren sich.
5. **Stumm bei Handy-Nutzung.** App im Vordergrund, oder iPhone entsperrt *und* in der Hand (Neigung plus Handzittern), pausiert die Wertung. Ein gesperrtes iPhone gilt nie als benutzt, egal wie es sich bewegt (Hosentasche), und ein entsperrtes, das unberührt auf dem Tisch liegt, auch nicht. Alle Signale werden jede Sekunde neu gelesen, damit keines hängen bleiben und den Coach dauerhaft stumm schalten kann.
6. **Begrenztes Auto-Zeroing.** Aufrechteres Sitzen wird schnell übernommen, Vorneigung nur sehr langsam und höchstens 4°. So kann die Baseline einen Rundrücken nie "lernen". Nach dem Aufstehen und Hinsetzen wird die neue Sitzposition innerhalb dieser Grenzen übernommen.
7. **Zwei Töne als festes Paar.** Wird die Haltung schlecht (Slouch-Load voll), kommt immer der tiefe, fallende Ton. Ist sie wieder gut (2 Sekunden im guten Bereich), kommt immer der helle, steigende Ton. Dazwischen gibt es keinen Cooldown. Bleibt die Haltung schlecht, erinnert Theo nach 40, 80, 160 Sekunden mit Stimme; nur diese Erinnerungen dünnen aus.

## Sperrbildschirm

Während einer Session liegt eine Karte auf dem Sperrbildschirm (Live Activity, auf neueren iPhones zusätzlich in der Dynamic Island): Score, Zustand (Aligned / Drifting / Slouching / ...) und Laufzeit. Sie ist zugleich die Kontrolle, ob die App im Hintergrund noch läuft: Die Session frischt sie mindestens einmal pro Minute auf. Bleibt das aus, zeigt die Karte nach etwa zweieinhalb Minuten "Not tracking".

- iOS erlaubt das Starten einer Live Activity nur im Vordergrund. Eine per Geofence automatisch gestartete Session bekommt ihre Karte beim nächsten Öffnen der App.
- Die Karte braucht die Widget-Extension `PostureWidgets`. Beim Sideloaden muss sie mit signiert werden (also "App Extensions entfernen" nicht wählen).
- Live Activities müssen in den iOS-Einstellungen unter *Posture* erlaubt sein.

## Stimme

Theo spricht über die iOS-Sprachausgabe und nimmt automatisch die beste installierte Stimme der Coach-Sprache (Premium vor Erweitert vor Standard). Ab Werk ist nur die Standard-Stimme installiert, und die klingt blechern. Eine natürliche Stimme lädt man einmal in den iOS-Einstellungen: *Bedienungshilfen > Gesprochene Inhalte > Stimmen > Deutsch*, dort z. B. Anna oder Petra in "Erweitert" oder "Premium". Im Profil lässt sich die Stimme auch fest wählen und probehören.

## Vor dem ersten echten Einsatz prüfen

- **Achsen-Vorzeichen**: `forwardSign` / `lateralSign` in `PostureTuning` einmal am Gerät verifizieren (Blick nach unten muss positiven Pitch ergeben).
- **Schwellen**: Die Werte sind aus der Biomechanik hergeleitet und gegen synthetische Signale getestet, nicht gegen echte AirPods-Aufnahmen.
- **Hintergrundbetrieb**: Die Session bleibt über eine stille Audio-Session am Leben (`UIBackgroundModes: audio`). Das ist der übliche Weg für solche Apps, im App Review aber erklärungsbedürftig. Fällt die Audio-Engine aus, startet die Session sie im Sekundentakt neu.
- **Auto-Start**: iOS weckt die App beim Betreten eines Geofence nur für wenige Sekunden. Sind die AirPods dann noch nicht verbunden, kommt stattdessen eine Benachrichtigung zum Antippen.

# Posture

iOS-App für Haltung und Rücken am Schreibtisch. Sie läuft auf zwei Arten:

- **Lernmodus**: Nach einer einstellbaren Sitzzeit (20 bis 60 Minuten) sagt die App, was jetzt nötig ist, passend zum Tagesplan aus Kalender und Standort. Keine Sensoren, kein Audio, nichts läuft im Hintergrund. Kostet praktisch keinen Akku, zählt als Sitzzeit und lässt sich per Siri starten.
- **Tracking**: Die Bewegungssensoren der AirPods messen Kopf- und Rückenhaltung. Das iPhone bleibt gesperrt; der Coach ("Theo") meldet sich bei echtem Zusammensacken und zusätzlich mit denselben Check-ins. Das ist der Modus, der Akku kostet, und er läuft nur, wenn man ihn startet.

Dazu kommen ohne laufende Session: ruhige Übungsvorschläge zuhause, die Schmerzfrage vor dem Schlafengehen und ein kleiner Kalender mit Sitzzeit und Schmerz der letzten drei Wochen.

Es gibt keinen Wochenplan und kein Wochenziel: getrackt wird, wann man will.

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
  App/            PostureApp, AppModel (Verdrahtung, Ankunft/Verlassen von Orten), StudyModeIntents (Siri), RootView, Tab-Bar
  Core/
    Posture/      PostureEngine (Heuristik), FatigueMonitor, Calibrator, SyntheticHead  – reines Swift, testbar
    Motion/       HeadphoneMotionService (CMHeadphoneMotionManager), PhoneContextService (Handy in Benutzung?)
    Plan/         DayPlan (Kalender + Standort -> Situation), Advisor (was ist jetzt nötig), Routine (Übungskatalog),
                  DayLog (Sitzzeit-Rechnung), AmbientPlanner (Schmerzfrage, Vorschläge zuhause) – reines Swift, testbar
                  CalendarService (EventKit), DayCoach (Check-ins: geplante Benachrichtigungen bzw. live in der Session)
    Guard/        LocationAndPowerGuard (Geofences, Standort-Check, Stromsparmodus, Akku), AutoStartPolicy (reine Regel)
    Audio/        AudioCoachService (Hintergrund-Audio, Chimes, Stimme), CoachVoice (Stimmenauswahl), CoachScript (Texte en/de)
    Session/      SessionManager, LiveActivityController (Karte auf dem Sperrbildschirm), SessionStore (Journal als JSON),
                  DayLogStore (Sitzzeit und Schmerz), SettingsStore, Notifier
  Models/         SessionRecord, DaySummary, UserSettings
  Design/         Theme, Komponenten, SpineOrbView, Charts, Illustrationen
  Features/       Home, Live, Insights, Tracker (Journal), DayLog (Kalender, Schmerz-Skala), Onboarding, Routine, Profile
PostureWidgets/   Widget-Extension: zeichnet die Live Activity (Sperrbildschirm, Dynamic Island)
Shared/           PostureActivityAttributes, von App und Extension gemeinsam kompiliert
PostureTests/     Szenario-Tests der Heuristik, Tagesplan und Check-ins, Auto-Start-Regel, FatigueMonitor
```

## Tagesplan: Kalender plus Standort

**Kalender.** Die App liest den iPhone-Kalender (EventKit), nur lesend. Alles, was in der Kalender-App synchronisiert ist, kommt automatisch an (iCloud, Google, abonnierte iCal-Feeds). Gelesen wird nur der **Titel**, und nur drei Dinge zählen:

- `lernen bib`: Lernen in der Bibliothek
- `lernen zuhause`: Lernen zuhause
- Gym (Stichwörter wie `gym`, `training`, `fitness`)

Vorlesungen, Räume und alles andere im Kalender werden ignoriert. Die Titel stehen im Profil und sind editierbar. Mehrwortige Titel werden als Text gesucht ("Lernen Bibliothek Mathe" passt auf `lernen bib`), kurze Einzelwörter müssen als ganzes Wort vorkommen.

**Standort-Check.** Der Kalender ist der Plan, der Standort die Kontrolle (`DayPlanner.resolve`):

- Ist das iPhone an einem gespeicherten Ort, gewinnt der Ort. Steht "lernen bib" im Kalender, das Handy ist aber zuhause, gilt: zuhause.
- An keinem gespeicherten Ort wird dem Kalender geglaubt. Ausnahme: Für genau diese Art Termin ist ein Ort gespeichert (Bibliothek, Zuhause, Gym) und das Handy ist nachweislich nicht dort. Dann gilt der Termin als ausgefallen.
- Orte: beliebig viele, also auch zwei Bibliotheken. Speichern, während man dort ist (Profil > Places).
- Technik: Geofences (Funkzellen/WLAN, kein GPS, wecken die App bei Ankunft und Verlassen) plus ein einzelner Standort-Fix beim Öffnen der App.

**Was wann vorgeschlagen wird** (`Advisor`):

| Situation | Vorschlag |
|---|---|
| Bibliothek / unterwegs | Augen + Haltung, Aufstehen, oberer Rücken im Wechsel |
| Gym in den nächsten 90 Minuten | nur Leichtes; zuhause Mobilität als Aufwärmen, keine Kraft |
| Im Gym | nichts |
| Zuhause | zusätzlich die Boden-Übungen: Wirbelsäulen-Flow, Rücken-Stabilität, Nervengleiten, Nervensystem runterfahren |
| Zuhause nach dem Gym oder abends | Runterfahren statt Kraft |
| Schmerz am Vorabend 6 oder mehr | nur Sanftes: Mobilität und Atmen, keine Kraft, kein Nervengleiten |

Die Boden-Übungen für Rücken und Nervensystem gibt es nur zuhause; woanders sind sie gesperrt. Rücken-Stabilität und Nervengleiten werden höchstens einmal am Tag vorgeschlagen.

## Zuhause: ruhige Vorschläge

Außerhalb des Lernmodus gibt es zuhause keinen Timer. Stattdessen höchstens zwei Vorschläge am Tag, ohne Ton und ausdrücklich freiwillig ("Wenn du magst ..."):

- nachmittags um 16:00, oder eine halbe Stunde nach dem Heimkommen, falls das später ist,
- eine Stunde vor der eingestellten Schlafenszeit: Runterfahren.

Vorgeschlagen wird die Boden-Übung, die am längsten nicht dran war. Kein Vorschlag, wenn kurz vorher schon eine Boden-Übung gemacht wurde. Verlässt man die Wohnung, werden die geplanten Vorschläge zurückgenommen (`AmbientPlanner`). Abschaltbar im Profil.

## Sitzzeit und Schmerz

**Sitzzeit** wird aus genau zwei Quellen gezählt (`SittingMath`, `DayLogStore`):

- Bibliothek: die ganze Aufenthaltszeit, automatisch per Geofence. Braucht Standort "Immer", sonst merkt die App das Verlassen nicht und zählt dort nur den Lernmodus.
- Lernmodus, egal wo, und Tracking, solange man dabei wirklich sitzt (siehe Punkt 10 unten). **Zuhause zählt nur das.**

Überschneidungen zählen einmal. Ein vergessener Lernmodus endet nach vier Stunden ohne Lebenszeichen.

**Siri.** "Hey Siri, mach Lernmodus an in Posture" geht sofort. Für den kurzen Satz ohne App-Namen einmalig in der Kurzbefehle-App einen Kurzbefehl mit dem Namen "Mach Lernmodus an" anlegen und die Aktion "Lernmodus starten" (Posture) hineinlegen; genauso "Lernmodus beenden". iOS verlangt den App-Namen in Sätzen, die ohne Einrichtung funktionieren.

**Schmerzfrage.** Zur eingestellten Schlafenszeit (Standard 22:30) kommt eine Benachrichtigung. Gedrückt halten für eine Schnellantwort (Keine / Leicht / Mittel / Stark), antippen für die Skala 0 bis 10. Ab 6 schlägt der Coach am nächsten Tag nur Sanftes vor.

**Kalender im Journal.** Die letzten drei Wochen, pro Tag die Sitzzeit als Zahl (h:mm) und darunter der Schmerzwert.

## Akku

- **Lernmodus** braucht keine laufende App: Die Check-ins der nächsten vier Stunden werden als lokale Benachrichtigungen bei iOS hinterlegt. Geplant wird neu, wenn die App geöffnet wird, wenn ein Ort betreten oder verlassen wird und nach jeder Übung. Verlässt man den Ort, an dem der Lernmodus gestartet wurde, endet er.
- **Tracking** kostet weiterhin Akku: Der AirPods-Sensorstream und die stille Audio-Session, die die App im Hintergrund wach hält, lassen sich nicht wegoptimieren. Gespart wird drumherum: Die Bewegungssensoren des iPhones laufen nur noch bei entsperrtem Gerät (5 statt 10 Hz), die Anzeige wird im Hintergrund nur einmal pro Sekunde aktualisiert, der Audio-Puffer ist groß gewählt (weniger Aufwachen), eine pausierte Session (AirPods raus) endet nach 8 statt 15 Minuten, und eine automatisch gestartete Session endet beim Verlassen des Ortes.
- Bei Ankunft in einer Bibliothek startet je nach Einstellung nichts, der Lernmodus (Standard) oder Tracking.

## Wie die Haltungserkennung funktioniert

Alle Schwellen stehen in `Core/Posture/PostureTuning.swift`.

1. **Nur Schwerkraft, kein Yaw.** Gemessen wird der Schwerkraftvektor im Kopfhörer-Koordinatensystem relativ zur kalibrierten Baseline. Stuhldrehen verändert ihn nicht.
2. **Leichte Vorneigung zum Bildschirm ist normal.** Die Baseline ist "aufrecht, Blick geradeaus". Am Monitor oder Laptop kippt der Kopf ein paar Grad nach vorn; die ersten 6° Vorneigung (`screenLean`) zählen deshalb gar nicht. Erst danach beginnen die Bänder: gut bis 14°, Slouch ab 22° Vorneigung.
3. **Wie der Kopf den guten Bereich verlässt, zählt mehr als der Winkel.** Langsames Driften (unter 8°/s) = Einsacken. Schnelles Kippen mit Absinken = Zusammenfallen. Schnelles Nicken (über 25°/s) gilt nur dann als bewusster Blick nach unten mit langer Leine, wenn der Kopf dabei tief geht (ab 26° Vorneigung, etwa Notizen auf dem Tisch). Wer schnell in eine mäßige Vorneigung fällt und dort bleibt, sackt ein, und das zählt wie Einsacken.
4. **Slouch-Load statt Timer.** Ein undichter Integrator füllt sich je nach Schwere und Kontext und leert sich bei guter Haltung. Kurze Ausreißer (Trinken, Blick zur Seite) füllen ihn nie, wiederholte addieren sich.
5. **Stumm nur, wenn das Handy in der Hand ist.** iPhone entsperrt *und* in der Hand (Neigung plus Handzittern) pausiert die Wertung. Die geöffnete App allein tut das nicht mehr: Liegt das Handy mit dem Live-Screen auf dem Tisch, kommen die Töne. Ein gesperrtes iPhone gilt nie als benutzt, egal wie es sich bewegt (Hosentasche). Alle Signale werden jede Sekunde neu gelesen, damit keines hängen bleiben und den Coach dauerhaft stumm schalten kann.
6. **Begrenztes Auto-Zeroing.** Aufrechteres Sitzen wird schnell übernommen, Vorneigung nur sehr langsam und höchstens 4°. So kann die Baseline einen Rundrücken nie "lernen". Nach dem Aufstehen und Hinsetzen wird die neue Sitzposition innerhalb dieser Grenzen übernommen.
7. **Zwei Beeps als festes Paar, keine Ansage.** Wird die Haltung schlecht (Slouch-Load voll), kommt ein kleiner tiefer Beep. Ist sie wieder gut (2 Sekunden im guten Bereich), kommt ein hellerer, freundlicherer aus zwei kurzen Tönen. Dazwischen gibt es keinen Cooldown. Bleibt die Haltung schlecht, kommt nach 40, 80, 160 Sekunden derselbe tiefe Beep doppelt; gesprochen wird zur Haltung nie. Im Live-Screen spielt "Play both beeps" beide Töne zur Probe ab.
8. **Empfindlichkeit einstellbar** (Profil, "How quickly it beeps"): Relaxed, Balanced (Standard) oder Quick, also etwa 40, 25 oder 15 Sekunden Einsacken bis zum Beep. Leichte Vorneigung zum Bildschirm (12°) bleibt in allen drei Stufen frei.
9. **Ein AirPod oder zwei.** iOS meldet pro Messwert, welcher AirPod ihn liefert, aber nicht, ob einer oder beide im Ohr sind. Jeder AirPod sitzt etwas anders und liefert deshalb um einige Grad andere Rohwinkel. Wechselt die Quelle (ein AirPod raus, oder iOS schaltet um), übernimmt die Engine die aktuelle Kopfhaltung auf den neuen AirPod, statt den Sprung als Einsacken zu werten. Der Live-Screen zeigt, welcher AirPod gerade misst.
10. **Sitzen wird erkannt.** Im Tracking zählt die Zeit erst als Sitzen, wenn der Körper 30 Sekunden ruhig war (rückwirkend ab Beginn der Ruhe). Wer mit AirPods herumläuft, sitzt nicht: Weggehen beendet das Zählen ab dem Moment, in dem die Bewegung begann. Stillstehen lässt sich von Sitzen nicht unterscheiden.

## Sperrbildschirm

Während einer Session liegt eine Karte auf dem Sperrbildschirm (Live Activity, auf neueren iPhones zusätzlich in der Dynamic Island): Score, Zustand (Aligned / Drifting / Slouching / ...) und Laufzeit. Sie ist zugleich die Kontrolle, ob die App im Hintergrund noch läuft: Die Session frischt sie mindestens einmal pro Minute auf. Bleibt das aus, zeigt die Karte nach etwa zweieinhalb Minuten "Not tracking".

- Die Karte gibt es nur im Tracking-Modus.
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
- **Kalender**: Home zeigt unter "Right now", welche Termine heute als Lernen oder Gym erkannt wurden.
- **Siri**: Ob "Mach Lernmodus an in Posture" auf einem deutsch eingestellten Gerät ohne Einrichtung erkannt wird, ist ungetestet. Der selbst angelegte Kurzbefehl funktioniert unabhängig davon.
- **Geplante Check-ins**: Der Plan wird nur neu gemacht, wenn die App aufwacht (Öffnen, Geofence). Ändert sich der Kalender, während die App geschlossen ist, gilt bis dahin der alte Plan.
- **Übungen**: allgemeine Mobilitäts- und Stabilitätsübungen, kein Ersatz für Physiotherapie. Bei Schmerzen weglassen.

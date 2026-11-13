# Alle Sounds der App

Stand: 13.11.2026. Diese Liste ist die Vorlage, um die Töne durch ElevenLabs-Sounds zu ersetzen.

**Wichtig:** Im Moment gibt es keine einzige Audiodatei in der App. Die Töne werden zur Laufzeit im Code berechnet (`Posture/Core/Audio/AudioCoachService.swift`, Funktion `playChime`), die Sprache kommt aus der iOS-Sprachausgabe. Die App lädt also noch keine Dateien. Wenn die neuen Sounds da sind, muss das Laden einmal eingebaut werden (siehe [So tauschen wir aus](#so-tauschen-wir-aus)).

## 1. Töne (7 Stück)

Das sind die eigentlichen Sounds. Sie spielen in den Modi **Voice** und **Chime**, im Modus **Silent** nie. Sie liegen über der Musik, die gerade läuft.

Klang heute: weiche Glocke (Sinuston plus zwei leise Obertöne, 10 ms Anschlag, klingt exponentiell aus).

| Dateiname (Vorschlag) | Wann | Klang heute | Länge heute | Lautstärke |
|---|---|---|---|---|
| `posture_bad` | Haltung ist gerade schlecht geworden | ein tiefer Ton, G4 (392 Hz) | 0,2 s | 0,32 (laut) |
| `posture_reminder` | Haltung ist immer noch schlecht (Erinnerung nach 40 s, danach mit 80 s, 160 s und 320 s Abstand) | derselbe tiefe Ton zweimal kurz hintereinander | 0,4 s | 0,32 (laut) |
| `posture_good` | Haltung ist wieder gut | zwei schnelle Töne aufwärts, E5 → H5 (659 → 988 Hz) | 0,4 s | 0,22 |
| `session_start` | Session startet, und wenn sie nach einer Pause weiterläuft | drei Töne aufwärts, C5 → E5 → G5 | 1,2 s | 0,2 |
| `session_end` | Session endet, und wenn sie wegen Stromsparmodus pausiert | drei Töne abwärts, G5 → E5 → C5 | 1,2 s | 0,2 |
| `upright_set` | Knopf „Upright set“ gedrückt | zwei Töne aufwärts, E5 → A5 | 0,9 s | 0,2 |
| `check_in` | Check-in während einer Tracking-Session („Zeit für …“) | drei Töne, C5 → G4 → C5 | 1,5 s | 0,2 |

Anhören: im Live-Screen spielt der Knopf **„Play both beeps“** `posture_bad` und danach `posture_good`.

Was die neuen Sounds können müssen:

- `posture_bad`, `posture_reminder` und `posture_good` kommen oft, teils mehrmals pro Minute. Kurz halten: höchstens 0,5 s, kein langer Nachhall.
- `posture_bad` tief und unaufdringlich, `posture_good` heller und freundlicher. Die beiden müssen sich ohne Hinsehen unterscheiden lassen.
- Alle müssen über Musik hörbar sein. Die Posture-Töne sind deshalb heute lauter als der Rest.
- Sauberer Anfang und sauberes Ende, keine Stille davor oder danach.

Vorschläge für die ElevenLabs-Sound-Effects-Eingabe (auf Englisch funktioniert sie am besten):

| Datei | Prompt | Dauer einstellen |
|---|---|---|
| `posture_bad` | `single soft low marimba note, warm, gentle, short, dry, no reverb` | 0,5 s |
| `posture_reminder` | `two soft low marimba notes, same pitch, quick double tap, dry, no reverb` | 0,6 s |
| `posture_good` | `two bright soft bell notes rising, cheerful, short, clean, light reverb` | 0,6 s |
| `session_start` | `three soft bell notes ascending, calm, welcoming, clean` | 1,5 s |
| `session_end` | `three soft bell notes descending, calm, closing, clean` | 1,5 s |
| `upright_set` | `two soft chime notes rising, confirmation sound, clean` | 1 s |
| `check_in` | `gentle three note chime, calm reminder, soft bell, clean` | 1,5 s |

## 2. Gesprochene Sätze (Theo)

Nur im Modus **Voice**. Gesprochen von der iOS-Sprachausgabe mit der Stimme aus dem Profil. Zur Haltung selbst sagt Theo nie etwas, dafür gibt es nur die Töne oben.

Diese Sätze ließen sich durch ElevenLabs-Sprachaufnahmen ersetzen. Die festen Sätze sind einfach, die zusammengesetzten nicht (siehe unten).

### Feste Sätze

| Schlüssel | Wann | Deutsch | Englisch |
|---|---|---|---|
| `say_session_start` | Session von Hand gestartet | Ich bin da. Sperr ruhig dein Handy. | I'm here. Go ahead and lock your phone. |
| `say_session_start_auto` | Session automatisch gestartet (Ankunft an einem Ort) | Posture Session gestartet. | Posture session started. |
| `say_session_end` | Session beendet | Session beendet. Gut gemacht. | Session ended. Nicely done. |
| `say_paused_low_power` | Stromsparmodus geht an | Stromsparmodus aktiv. Ich pausiere. | Low Power Mode is on. I'll pause. |
| `say_resumed` | Session läuft nach einer Pause weiter | Weiter geht's. | Back on. |
| `say_upright_set` | Knopf „Upright set“ | Aufrecht gespeichert. | Upright set. |
| `say_preview` | Stimme im Profil ausprobieren | Hallo, ich bin Theo. Schultern locker, Rücken lang. | Hi, I'm Theo. Soft shoulders, long spine. |

Vor jedem dieser Sätze spielt der passende Ton aus Abschnitt 1, außer bei der Stimmprobe im Profil.

### Zusammengesetzte Sätze

Diese entstehen aus Bausteinen und enthalten Zahlen. Als fertige Aufnahme gehen sie nur, wenn man jeden Baustein einzeln aufnimmt.

**Check-in während einer Tracking-Session:** Anlass + „Zeit für *Übung*, *Dauer*.“ + Hinweis. Beispiel: „45 Minuten ohne Pause. Zeit für Augen und Haltung, 30 Sekunden. Geht leise am Platz.“

- Anlass: „*N* Minuten ohne Pause.“ / „Deine Haltung lässt seit ein paar Minuten nach.“ / „Du sackst immer wieder ein.“ / „Du sitzt schon lange.“
- Übung (gesprochener Name): Augen und Haltung · Aufstehen und Bewegen · den oberen Rücken · einen Wirbelsäulen-Flow auf dem Boden · Rücken-Stabilität · sanftes Nervengleiten · ruhiges Atmen im Liegen
- Hinweis: „Du bist zuhause, also gern auf dem Boden.“ / „Kurz raus aus dem Lesesaal.“ / „Geht leise am Platz.“ / „Gym in *N* Minuten: nur locker machen, die Kraft sparst du dir fürs Training.“ / „Nach dem Training: runterfahren statt nachlegen.“ / „Abends lieber runterfahren.“ / „Ganz in Ruhe, kein Muss.“ / „Wegen der Schmerzen heute nur Sanftes.“

**Check-in in der Uni:** dort gibt es keine Übung, nur eine Ansage. Anlass + „Kurz aufrichten und durchatmen.“ (englisch: „Sit tall for a moment and take a breath.“)

Die Texte stehen in `Posture/Core/Plan/Advisor.swift` (`AdviceText`).

**Übungsschritte:** In einer Übung liest Theo jeden Schritt vor, Titel und Anleitung. Das sind 8 Übungen mit zusammen 31 Schritten, jeweils auf Deutsch und Englisch. Feste Texte, also aufnehmbar, aber viele. Sie stehen in `Posture/Core/Plan/Routine.swift`.

## 3. Töne, die von iOS kommen

Diese gehören nicht zur App und lassen sich nur teilweise ersetzen.

| Was | Wann | Ersetzbar? |
|---|---|---|
| Standard-Benachrichtigungston | Check-ins im Lernmodus, die Schmerzfrage vor dem Schlafen, der Hinweis „You're at …, put in your AirPods“ | Ja, mit einer eigenen Datei im App-Paket (höchstens 30 s, `.caf`, `.wav` oder `.aiff`). Vorschlag für den Namen: `notification` |
| Siri-Antwort | „Lernmodus ist an …“ nach dem Siri-Befehl | Nein, das spricht Siri |
| Haptik | Wechsel zum nächsten Schritt in einer Übung | Kein Ton, nur ein Tippen |

Ohne Ton kommen: „Study mode on/off“, „Posture session started/ended“, die ruhigen Vorschläge zuhause und alle Benachrichtigungen im Modus Silent.

## So tauschen wir aus

1. Sounds in ElevenLabs erzeugen und mit genau den Dateinamen aus Abschnitt 1 speichern, zum Beispiel `posture_bad.wav`. Format: WAV oder M4A, 44,1 kHz. Mono oder Stereo ist egal.
2. Die Dateien in einen neuen Ordner `Posture/Sounds/` legen.
3. Danach baue ich das Laden ein: Die App spielt die Datei, wenn sie da ist, und fällt sonst auf den berechneten Ton zurück. So kann man auch nur einzelne Töne ersetzen.

Für Theos Stimme (Abschnitt 2) lohnt sich als erster Schritt nur die Tabelle „Feste Sätze“: sieben Aufnahmen pro Sprache, Dateiname gleich Schlüssel plus Sprache, zum Beispiel `say_session_end_de.m4a`.

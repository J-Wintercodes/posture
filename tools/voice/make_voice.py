"""Records Theo's voice with Piper, a free text-to-speech that runs offline.

Everything Theo says is fixed text in the Swift code. This script collects
those sentences, renders each one once as a small .m4a file and puts it into
Posture/Sounds/Voice. The app plays the file instead of the iOS voice
(`VoiceClips.swift`). A sentence without a file falls back to the iOS voice,
so nothing breaks when a text changes and this script was not run again.

Run it again after changing a spoken text:

    python -m venv .venv
    .venv\\Scripts\\pip install piper-tts imageio-ffmpeg
    .venv\\Scripts\\python tools\\voice\\make_voice.py

The voices are downloaded on the first run (about 120 MB each, into
tools/voice/models, which git ignores). Only new or changed sentences are
rendered; files for sentences that are gone are deleted.

The file names come from a hash of the sentence, see `clip_name`. It must
stay the same as `VoiceClips.clipName` in Swift.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import unicodedata
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Posture" / "Sounds" / "Voice"
MODELS = Path(__file__).resolve().parent / "models"
LIST = Path(__file__).resolve().parent / "sentences.txt"

# Thorsten: CC0. Ryan: CC BY-NC-SA 4.0 (fine for a private app, not for sale).
VOICES = {
    "de": "de_DE-thorsten-high",
    "en": "en_US-ryan-high",
}
# Above 1 is slower. Theo is calm, not rushed.
LENGTH_SCALE = {"de": 1.08, "en": 1.05}

# Check-in minutes that are said aloud. Sitting time is rounded to five
# minutes (CheckInPlanner.roundedMinutes); gym lead is at most 90 minutes
# (DayPlan.gymLead). Anything outside falls back to the iOS voice.
SITTING_MINUTES = range(5, 301, 5)
GYM_MINUTES = range(1, 91)


# MARK: Sentences, exactly as VoiceClips.swift splits them

def normalize(text: str) -> str:
    return unicodedata.normalize("NFC", " ".join(text.split()))


def chunks(text: str) -> list[str]:
    """Sentences: cut after . ! or ? when a space follows."""
    text = normalize(text)
    parts = re.split(r"(?<=[.!?]) ", text)
    return [p for p in parts if p]


def clip_name(language: str, sentence: str) -> str:
    """FNV-1a, 64 bit, over the UTF-8 bytes of "<language>|<sentence>"."""
    h = 0xCBF29CE484222325
    for b in f"{language}|{normalize(sentence)}".encode("utf-8"):
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"v_{language}_{h:016x}"


# MARK: Reading the texts out of the Swift code

STR = r'"((?:[^"\\]|\\.)*)"'


def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\")


def section(source: str, start: str, end: str | None) -> str:
    i = source.index(start)
    j = source.index(end, i) if end else len(source)
    return source[i:j]


def ternaries(source: str) -> list[tuple[str, str]]:
    """`de ? "x" : "y"` → (de, en)."""
    return [(unescape(d), unescape(e)) for d, e in re.findall(r"\?\s*" + STR + r"\s*:\s*" + STR, source)]


def expand(text: str) -> list[str]:
    """Fills in the minutes of an interpolated sentence."""
    if "\\(" not in text:
        return [text]
    if "\\(minutes)" in text and text.startswith("Gym"):
        return [text.replace("\\(minutes)", str(m)) for m in GYM_MINUTES]
    if "\\(minutes)" in text:
        return [text.replace("\\(minutes)", str(m)) for m in SITTING_MINUTES]
    raise ValueError(f"Unknown interpolation, teach make_voice.py about it: {text}")


def duration_words(seconds: int, language: str) -> str:
    """Routine.durationWords"""
    de = language == "de"
    if seconds < 60:
        return f"{seconds} Sekunden" if de else f"{seconds} seconds"
    minutes = int(seconds / 60 + 0.5)
    if minutes == 1:
        return "eine Minute" if de else "one minute"
    return f"{minutes} Minuten" if de else f"{minutes} minutes"


def routines(source: str) -> list[dict]:
    found = []
    for block in re.split(r"static let \w+ = Routine\(", source)[1:]:
        spoken = re.search(r"spokenName:\s*Localized\(\s*" + STR + r"\s*,\s*" + STR, block, re.S)
        steps = re.findall(
            r"title:\s*Localized\(\s*" + STR + r"\s*,\s*" + STR + r"\s*\),\s*"
            r"cue:\s*Localized\(\s*" + STR + r"\s*,\s*" + STR + r"\s*\),\s*"
            r"seconds:\s*(\d+)",
            block,
            re.S,
        )
        found.append({
            "spoken": {"en": unescape(spoken.group(1)), "de": unescape(spoken.group(2))},
            "steps": [
                {"title": {"en": unescape(te), "de": unescape(td)}, "cue": {"en": unescape(ce), "de": unescape(cd)}}
                for te, td, ce, cd, _ in steps
            ],
            "seconds": sum(int(s[4]) for s in steps),
        })
    return found


def sentences() -> dict[str, set[str]]:
    texts: dict[str, list[str]] = {"de": [], "en": []}

    def add(de: str, en: str) -> None:
        texts["de"].extend(expand(de))
        texts["en"].extend(expand(en))

    # Theo's own lines. Posture nudges are beeps only, so they are left out.
    script = (ROOT / "Posture/Core/Audio/CoachScript.swift").read_text("utf-8")
    for de, en in ternaries(section(script, "static func preview", "static func notification")):
        add(de, en)
    for de, en in ternaries(section(script, "private static func lines", "private static func nudgeLines")):
        add(de, en)

    # Check-ins: lead, "Time for ...", hint.
    advisor = (ROOT / "Posture/Core/Plan/Advisor.swift").read_text("utf-8")
    advice = section(advisor, "static func announcement", "private static func join")
    for de, en in ternaries(advice):
        if "\\(routine" in de:
            continue
        add(de, en)

    for routine in routines((ROOT / "Posture/Core/Plan/Routine.swift").read_text("utf-8")):
        for lang, lead in (("de", "Zeit für"), ("en", "Time for")):
            texts[lang].append(f"{lead} {routine['spoken'][lang]}, {duration_words(routine['seconds'], lang)}.")
        # RoutinePlayerView reads "<title>. <cue>".
        for step in routine["steps"]:
            for lang in ("de", "en"):
                texts[lang].append(f"{step['title'][lang]}. {step['cue'][lang]}")

    return {lang: {c for t in items for c in chunks(t)} for lang, items in texts.items()}


# MARK: Rendering

def ensure_model(name: str) -> Path:
    path = MODELS / f"{name}.onnx"
    if not path.exists():
        MODELS.mkdir(parents=True, exist_ok=True)
        subprocess.run([sys.executable, "-m", "piper.download_voices", "--data-dir", str(MODELS), name], check=True)
    return path


def render(voice, config, text: str, target: Path, ffmpeg: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "raw.wav"
        with wave.open(str(raw), "wb") as wav:
            voice.synthesize_wav(text, wav, syn_config=config)
        # Cut the silence at both ends, bring it to an even loudness that
        # carries over music, then a small mono AAC file.
        trim = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03"
        chain = f"{trim},areverse,{trim},areverse,loudnorm=I=-16:TP=-1.5:LRA=11"
        subprocess.run(
            [ffmpeg, "-loglevel", "error", "-y", "-i", str(raw), "-af", chain,
             "-ar", "22050", "-ac", "1", "-c:a", "aac", "-b:a", "48k", str(target)],
            check=True,
        )


def main() -> None:
    from piper import PiperVoice, SynthesisConfig
    import imageio_ffmpeg

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    wanted = sentences()
    OUT.mkdir(parents=True, exist_ok=True)

    names: dict[str, tuple[str, str]] = {}
    for lang, items in wanted.items():
        for sentence in items:
            names[clip_name(lang, sentence)] = (lang, sentence)

    with LIST.open("w", encoding="utf-8", newline="\n") as f:
        for name, (lang, sentence) in sorted(names.items(), key=lambda kv: (kv[1][0], kv[1][1])):
            f.write(f"{name}\t{sentence}\n")

    for old in OUT.glob("v_*.m4a"):
        if old.stem not in names:
            old.unlink()
            print("removed", old.name)

    todo = [(n, l, s) for n, (l, s) in names.items() if not (OUT / f"{n}.m4a").exists()]
    print(f"{len(names)} sentences, {len(todo)} to render")
    loaded = {}
    for i, (name, lang, sentence) in enumerate(sorted(todo, key=lambda t: t[1]), 1):
        if lang not in loaded:
            loaded[lang] = PiperVoice.load(str(ensure_model(VOICES[lang])))
        config = SynthesisConfig(length_scale=LENGTH_SCALE[lang])
        render(loaded[lang], config, sentence, OUT / f"{name}.m4a", ffmpeg)
        print(f"[{i}/{len(todo)}] {lang}: {sentence}")


if __name__ == "__main__":
    if "--list" in sys.argv:
        for lang, items in sentences().items():
            for s in sorted(items):
                print(lang, clip_name(lang, s), s, sep="\t")
    else:
        main()

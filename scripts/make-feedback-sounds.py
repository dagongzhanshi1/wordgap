"""Generate deterministic, softly struck chime motifs without external assets."""
from pathlib import Path
import math
import struct
import wave

resources = Path(__file__).resolve().parent.parent / "Resources"
rate = 44100
# start, duration, frequency, relative level
motifs = {
    "forgot": [(0, .19, 659.25, 1), (.09, .19, 587.33, .85)],
    "vague": [(0, .18, 698.46, 1), (.15, .18, 698.46, .85)],
    "knew": [(0, .22, 783.99, .85), (.11, .22, 987.77, 1)],
    "mastered": [(0, .22, 783.99, .75), (.09, .22, 987.77, .85), (.18, .22, 1174.66, 1)],
}
for name, notes in motifs.items():
    duration = max(start + length for start, length, *_ in notes)
    samples = []
    for i in range(round(duration * rate)):
        t = i / rate
        signal = 0
        for start, length, frequency, level in notes:
            local = t - start
            if not 0 <= local < length:
                continue
            attack = math.sin(math.pi / 2 * min(1, local / .006)) ** 2
            release = math.sin(math.pi / 2 * min(1, (length - local) / .06)) ** 2
            # A softly struck resonator: bright upper modes decay before the rounded body.
            modes = (
                math.sin(2 * math.pi * frequency * local) * math.exp(-local / .085)
                + .24 * math.sin(2 * math.pi * frequency * 2.76 * local) * math.exp(-local / .025)
                + .045 * math.sin(2 * math.pi * frequency * 5.4 * local) * math.exp(-local / .012)
            )
            signal += level * attack * release * modes
        samples.append(signal)
    gain = .28 / max(abs(s) for s in samples)
    pcm = b"".join(struct.pack("<h", round(s * gain * 32767)) for s in samples)
    with wave.open(str(resources / f"feedback-{name}.wav"), "wb") as output:
        output.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        output.writeframes(pcm)

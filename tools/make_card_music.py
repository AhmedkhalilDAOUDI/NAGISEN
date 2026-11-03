"""Synthesizes the three short tracks a share card can carry (NAGISEN/card_*.m4a).

Every sound is made here from sine waves, plucked strings and noise, so the app owns the music
outright. Run from the repo root: python3 tools/make_card_music.py (needs macOS afconvert).
"""
import array, math, os, random, subprocess, tempfile, wave

RATE = 44100
SECONDS = 20
N = RATE * SECONDS
OUT = os.path.join(os.path.dirname(__file__), "..", "NAGISEN")


def hz(note):
    """MIDI note number to frequency."""
    return 440.0 * 2 ** ((note - 69) / 12)


def envelope(i, length, attack, release):
    t = i / RATE
    end = length / RATE
    if t < attack:
        return t / attack
    if t > end - release:
        return max(0.0, (end - t) / release)
    return 1.0


def pad(buf, notes, start, length, level):
    """Soft chord: two slightly detuned sines per note plus a quiet octave."""
    a = int(start * RATE)
    n = int(length * RATE)
    for note in notes:
        f = hz(note)
        for detune, gain in ((0.9985, 0.5), (1.0015, 0.5), (2.0, 0.12)):
            step = 2 * math.pi * f * detune / RATE
            phase = random.random() * 6.28
            for i in range(n):
                if a + i >= N:
                    break
                buf[a + i] += math.sin(phase + step * i) * gain * level * envelope(i, n, 1.6, 1.8)


def pluck(buf, note, start, level, decay=0.996):
    """Karplus-Strong string: a burst of noise through a short averaging delay line."""
    period = max(2, int(RATE / hz(note)))
    line = [random.uniform(-1, 1) for _ in range(period)]
    mean = sum(line) / period
    line = [v - mean for v in line]  # a noise burst with an offset leaves a DC hum behind
    a = int(start * RATE)
    for i in range(int(RATE * 2.5)):
        if a + i >= N:
            break
        j = i % period
        sample = line[j]
        line[j] = decay * 0.5 * (sample + line[(j + 1) % period])
        buf[a + i] += sample * level


def kick(buf, start, level):
    a = int(start * RATE)
    phase = 0.0
    for i in range(int(RATE * 0.35)):
        if a + i >= N:
            break
        t = i / RATE
        phase += 2 * math.pi * (45 + 75 * math.exp(-t * 30)) / RATE
        buf[a + i] += math.sin(phase) * math.exp(-t * 9) * level


def shaker(buf, start, level):
    a = int(start * RATE)
    last = 0.0
    for i in range(int(RATE * 0.06)):
        if a + i >= N:
            break
        noise = random.uniform(-1, 1)
        high = noise - last  # crude high-pass keeps it airy, not hissy
        last = noise
        buf[a + i] += high * math.exp(-i / RATE * 70) * level


def bass(buf, note, start, length, level):
    a = int(start * RATE)
    n = int(length * RATE)
    step = 2 * math.pi * hz(note) / RATE
    for i in range(n):
        if a + i >= N:
            break
        buf[a + i] += math.sin(step * i) * level * envelope(i, n, 0.02, 0.25)


def reverb(dry, seed):
    """Small Schroeder room: four combs into two all-passes. The seed spreads left from right."""
    combs = [d + seed for d in (1557, 1617, 1491, 1422)]
    wet = [0.0] * N
    for d in combs:
        line = [0.0] * d
        for i in range(N):
            j = i % d
            out = line[j]
            line[j] = dry[i] + out * 0.82
            wet[i] += out * 0.25
    for d in (225 + seed // 3, 556 + seed // 3):
        line = [0.0] * d
        for i in range(N):
            j = i % d
            buffered = line[j]
            line[j] = wet[i] + buffered * 0.5
            wet[i] = buffered - wet[i] * 0.5
    return wet


def finish(name, dry, wet_mix):
    left_wet, right_wet = reverb(dry, 0), reverb(dry, 23)
    frames = []
    for i in range(N):
        fade = min(1.0, i / (RATE * 0.6), (N - i) / (RATE * 2.0))
        frames.append(((dry[i] + left_wet[i] * wet_mix) * fade, (dry[i] + right_wet[i] * wet_mix) * fade))
    peak = max(max(abs(l), abs(r)) for l, r in frames) or 1.0
    gain = 0.8 / peak
    pcm = array.array("h", (int(v * gain * 32767) for frame in frames for v in frame))
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        target = os.path.join(OUT, f"card_{name}.m4a")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "160000", wav_path, target], check=True)
    print("wrote", os.path.normpath(target))


def still():
    """Slow pads: Am9, Fmaj7, Cmaj7, G6, five seconds each."""
    buf = [0.0] * N
    for k, chord in enumerate(([45, 57, 60, 64, 71], [41, 57, 60, 64, 69], [36, 55, 59, 64, 67], [43, 55, 59, 64, 69])):
        pad(buf, chord, k * 5.0, 6.2, 0.16)
    return buf


def dusk():
    """Plucked D minor pentatonic over a quiet drone, 72 beats a minute."""
    buf = [0.0] * N
    pad(buf, [38, 50, 57], 0, SECONDS, 0.10)
    beat = 60 / 72
    phrase = [62, 69, 72, 74, 69, 67, 65, 62, 60, 65, 67, 69, 72, 69, 67, 65]
    for k in range(int(SECONDS / (beat / 2)) - 2):
        note = phrase[k % len(phrase)]
        pluck(buf, note, k * beat / 2, 0.30 if k % 4 == 0 else 0.20)
    return buf


def pulse():
    """A steady 96 bpm for training: soft kick, shaker on the off-beats, bass and pads."""
    buf = [0.0] * N
    beat = 60 / 96
    beats = int(SECONDS / beat)
    for k in range(beats):
        kick(buf, k * beat, 0.55)
        shaker(buf, k * beat + beat / 2, 0.10)
    roots = [45, 41, 48, 43]
    for bar in range(beats // 4 + 1):
        root = roots[bar % 4]
        for k in range(4):
            bass(buf, root, (bar * 4 + k) * beat + beat / 2, beat * 0.45, 0.22)
    for k, chord in enumerate(([57, 60, 64], [57, 60, 65], [55, 60, 64], [55, 59, 62])):
        for repeat in range(0, SECONDS, 10):
            pad(buf, chord, repeat + k * 2.5, 3.0, 0.07)
    return buf


if __name__ == "__main__":
    random.seed(7)
    finish("still", still(), 0.35)
    finish("dusk", dusk(), 0.30)
    finish("pulse", pulse(), 0.18)

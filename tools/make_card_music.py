"""Synthesizes the short tracks a share card can carry (NAGISEN/card_*.m4a), and with `dojo`, the hideout's music.

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


def bell(buf, note, start, level, ring=4.0):
    """Struck bell: a few inharmonic partials, the higher ones dying first."""
    a = int(start * RATE)
    f = hz(note)
    for ratio, gain in ((1.0, 1.0), (2.76, 0.35), (5.4, 0.15), (8.93, 0.06)):
        step = 2 * math.pi * f * ratio / RATE
        for i in range(int(RATE * ring)):
            if a + i >= N:
                break
            t = i / RATE
            buf[a + i] += math.sin(step * i) * gain * level * math.exp(-t * ratio * 1.2) * min(1.0, t * 400)


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


def finish(name, dry, wet_mix, prefix="card_"):
    # Remove any slow drift (noise sources wander), which would thump where a track loops.
    previous = carried = 0.0
    for i, sample in enumerate(dry):
        carried = sample - previous + 0.999 * carried
        previous = sample
        dry[i] = carried
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
        target = os.path.join(OUT, f"{prefix}{name}.m4a")
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


def tide():
    """Wide pads that swell and fall back: Dmaj9, Bm7, Gmaj7, A6."""
    buf = [0.0] * N
    for k, chord in enumerate(([38, 54, 57, 61, 64], [35, 54, 57, 62, 66], [31, 50, 54, 59, 62], [33, 52, 57, 61, 66])):
        pad(buf, chord, k * 5.0, 6.4, 0.15)
    return buf


def lantern():
    """Slow bells on C pentatonic over a low drone."""
    buf = [0.0] * N
    pad(buf, [36, 43, 48], 0, SECONDS, 0.09)
    tune = [72, 76, 79, 76, 74, 72, 69, 72, 74, 79, 81, 79, 76, 74, 72, 67]
    for k, note in enumerate(tune):
        bell(buf, note, 0.3 + k * 1.2, 0.16 if k % 4 == 0 else 0.11)
    return buf


def steps():
    """A walking pace, 110 bpm: kick on one and three, plucked line, bass."""
    buf = [0.0] * N
    beat = 60 / 110
    beats = int(SECONDS / beat)
    line = [64, 67, 71, 67, 62, 66, 69, 66, 60, 64, 67, 64, 62, 66, 69, 71]
    roots = [40, 38, 36, 38]
    for k in range(beats):
        if k % 2 == 0:
            kick(buf, k * beat, 0.45)
        shaker(buf, k * beat + beat / 2, 0.07)
        pluck(buf, line[k % len(line)], k * beat, 0.20)
        if k % 2 == 1:
            bass(buf, roots[(k // 4) % 4], k * beat, beat * 0.8, 0.20)
    return buf


def ember():
    """Warm low pads with a slow E minor arpeggio, 60 bpm."""
    buf = [0.0] * N
    for k, chord in enumerate(([28, 40, 47, 55], [24, 36, 43, 52], [31, 43, 50, 55], [26, 38, 45, 54])):
        pad(buf, chord, k * 5.0, 6.0, 0.13)
    arp = [52, 55, 59, 62, 48, 52, 55, 59, 55, 59, 62, 67, 50, 54, 57, 62]
    for k in range(SECONDS - 1):
        pluck(buf, arp[k % len(arp)], k + 0.5, 0.18, decay=0.997)
    return buf


def atlas():
    """D Hijaz: plucked oud-like phrases over a frame-drum pattern, 90 bpm."""
    buf = [0.0] * N
    beat = 60 / 90
    beats = int(SECONDS / beat)
    pad(buf, [38, 45, 50], 0, SECONDS, 0.08)
    for k in range(beats):
        kick(buf, k * beat, 0.42 if k % 4 in (0, 3) else 0.22)
        shaker(buf, k * beat + beat / 2, 0.08)
        shaker(buf, k * beat + beat * 0.75, 0.05)
    # D, Eb, F#, G, A, Bb, C: the bright step from Eb to F# is what makes it sound Hijaz.
    phrase = [62, 63, 66, 67, 69, 67, 66, 63, 62, 60, 62, 63, 66, 69, 70, 69, 67, 66, 63, 62]
    for k in range(beats * 2 - 4):
        if k % 8 != 7:
            pluck(buf, phrase[k % len(phrase)], k * beat / 2, 0.24 if k % 4 == 0 else 0.17)
    return buf


def sunrise():
    """A rising G major arpeggio that keeps climbing, 80 bpm."""
    buf = [0.0] * N
    for k, chord in enumerate(([43, 55, 59, 62], [40, 52, 55, 59], [36, 52, 55, 60], [38, 54, 57, 62])):
        pad(buf, chord, k * 5.0, 6.0, 0.10)
    beat = 60 / 80
    shapes = [[67, 71, 74, 79], [64, 67, 71, 76], [60, 64, 67, 72], [62, 66, 69, 74]]
    for k in range(int(SECONDS / (beat / 2)) - 2):
        shape = shapes[int(k * beat / 2 / 5.0) % 4]
        pluck(buf, shape[k % 4] + 12 * ((k // 4) % 2), k * beat / 2, 0.16)
    return buf


def rain():
    """Scattered high drops over a soft A minor pad, never landing on the beat."""
    buf = [0.0] * N
    for k, chord in enumerate(([45, 57, 60, 64], [41, 57, 60, 65], [43, 55, 59, 62], [45, 57, 60, 64])):
        pad(buf, chord, k * 5.0, 6.0, 0.11)
    notes = [76, 79, 81, 84, 86, 88]
    t = 0.4
    while t < SECONDS - 2.5:
        pluck(buf, random.choice(notes), t, random.uniform(0.08, 0.16), decay=0.994)
        t += random.uniform(0.25, 0.9)
    for k in range(int(SECONDS / 0.5)):
        shaker(buf, k * 0.5 + 0.25, 0.03)
    return buf


def run():
    """128 bpm for hard sessions: kick every beat, shaker on eighths, driving bass."""
    buf = [0.0] * N
    beat = 60 / 128
    beats = int(SECONDS / beat)
    roots = [45, 45, 41, 43]
    for k in range(beats):
        kick(buf, k * beat, 0.55)
        shaker(buf, k * beat + beat / 2, 0.10)
        shaker(buf, k * beat, 0.04)
        root = roots[(k // 4) % 4]
        bass(buf, root, k * beat + beat / 2, beat * 0.4, 0.20)
    for k, chord in enumerate(([57, 60, 64], [57, 60, 64], [53, 57, 60], [55, 59, 62])):
        for repeat in range(0, SECONDS, 8):
            pad(buf, chord, repeat + k * 2.0, 2.4, 0.06)
    return buf


def breath():
    """Slow swells to breathe with: in as it rises, out as it falls."""
    buf = [0.0] * N
    for k in range(4):
        chord = [50, 57, 62, 66] if k % 2 == 0 else [47, 54, 59, 62]
        pad(buf, chord, k * 5.0, 5.0, 0.18)
    return buf


def night():
    """Low bells in F minor over a deep drone, with a lot of space."""
    buf = [0.0] * N
    pad(buf, [29, 41, 48], 0, SECONDS, 0.10)
    for k, note in enumerate([65, 68, 72, 70, 68, 63, 65, 60]):
        bell(buf, note, 0.5 + k * 2.3, 0.15, ring=5.0)
    return buf


def shakuhachi(buf, note, start, length, level):
    """A breathy bamboo flute: a soft tone that swells, wavers more as it is held, and carries air."""
    a = int(start * RATE)
    n = int(length * RATE)
    f = hz(note)
    phase = 0.0
    air = 0.0
    for i in range(n):
        if a + i >= N:
            break
        t = i / RATE
        vibrato = 1 + 0.006 * min(1.0, t / 1.5) * math.sin(2 * math.pi * 5.2 * t)
        phase += 2 * math.pi * f * vibrato / RATE
        air = air * 0.9 + random.uniform(-1, 1) * 0.1  # softened noise, the breath in the bamboo
        tone = math.sin(phase) + 0.18 * math.sin(2 * phase) + 0.06 * math.sin(3 * phase)
        buf[a + i] += (tone + air * 1.6) * level * envelope(i, n, 0.7, 1.2)


def wind(buf, level):
    """Air moving through the garden, rising and falling slowly."""
    low = 0.0
    for i in range(N):
        low = low * 0.995 + random.uniform(-1, 1) * 0.005
        swell = 0.6 + 0.4 * math.sin(2 * math.pi * i / RATE / 23)
        buf[i] += low * 6 * level * swell


def chirp(buf, start, level):
    """A small bird: two quick rising whistles."""
    for k in range(2):
        a = int((start + k * 0.12) * RATE)
        phase = 0.0
        for i in range(int(RATE * 0.07)):
            if a + i >= N:
                break
            t = i / (RATE * 0.07)
            phase += 2 * math.pi * (2600 + 1400 * t) / RATE
            buf[a + i] += math.sin(phase) * level * math.sin(math.pi * t)


def soften(buf, amount):
    """A gentle low-pass, rounding off the bright edge of plucked strings."""
    last = 0.0
    for i in range(len(buf)):
        last += (buf[i] - last) * amount
        buf[i] = last


def dojo():
    """For Kuro's hideout: an unhurried, sunny garden. Koto phrases in the bright yo scale over warm major
    chords, a few soft bells, birds now and then. Nothing breathy, nothing minor."""
    buf = [0.0] * N
    # Dmaj9, Gmaj7, Bm7, A6sus: warm, open, always resolving home.
    for k, chord in enumerate([[50, 57, 61, 64, 66], [43, 55, 59, 62, 66], [47, 54, 57, 62, 66], [45, 52, 57, 62, 66]] * 6):
        pad(buf, chord, k * 4.0, 5.0, 0.055)
    strings = [0.0] * N
    # D yo scale: D, E, G, A, B, across two octaves.
    scale = [62, 64, 67, 69, 71, 74, 76, 79, 81, 83]
    t = 1.0
    while t < SECONDS - 6:
        position = random.randrange(3, 7)
        for _ in range(random.randrange(4, 7)):
            position = max(0, min(len(scale) - 1, position + random.choice([-1, -1, 1, 1, 2, -2])))
            pluck(strings, scale[position], t, random.uniform(0.14, 0.2), decay=0.996)
            t += random.choice([0.5, 0.75, 0.75, 1.0])
        if random.random() < 0.5:
            bell(buf, random.choice([86, 88, 91]), t + 0.3, 0.035, ring=3.0)
        if random.random() < 0.35:
            chirp(buf, t + random.uniform(0.5, 1.5), 0.04)
        t += random.uniform(1.8, 3.0)
    soften(strings, 0.35)
    for i in range(N):
        buf[i] += strings[i]
    return buf


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["dojo"]:
        # The hideout's music only: longer, so its loop comes round rarely.
        random.seed(19)
        SECONDS = 96
        N = RATE * SECONDS
        finish("dojo_music", dojo(), 0.45, prefix="")
        sys.exit()
    random.seed(7)
    finish("still", still(), 0.35)
    finish("dusk", dusk(), 0.30)
    finish("pulse", pulse(), 0.18)
    finish("tide", tide(), 0.35)
    finish("lantern", lantern(), 0.40)
    finish("steps", steps(), 0.20)
    finish("ember", ember(), 0.30)
    finish("atlas", atlas(), 0.25)
    finish("sunrise", sunrise(), 0.30)
    finish("rain", rain(), 0.35)
    finish("run", run(), 0.15)
    finish("breath", breath(), 0.40)
    finish("night", night(), 0.45)

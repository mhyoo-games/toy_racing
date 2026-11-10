"""효과음·배경음을 코드로 합성해 assets/sfx, assets/music 에 wav로 쓴다.
python3 tools/sound/gen.py   (외부 음원 없음, 표준 라이브러리만. 같은 결과가 나오게 난수 씨앗 고정)
"""
import array, math, os, random, wave

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets')


def write(path, data, sr=SR, norm=0.9):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(x) for x in data))
    g = norm / peak
    a = array.array('h', (int(max(-1.0, min(1.0, x * g)) * 32000) for x in data))
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(a.tobytes())


def osc(kind, ph):
    p = ph % 1.0
    if kind == 'sin':
        return math.sin(2 * math.pi * p)
    if kind == 'tri':
        return 4 * abs(p - 0.5) - 1
    if kind == 'sq':
        return 1.0 if p < 0.5 else -1.0
    if kind == 'pul':
        return 1.0 if p < 0.25 else -1.0
    if kind == 'saw':
        return 2 * p - 1
    return 0.0


def env(t, dur, a=0.005, r=0.05):
    if t < a:
        return t / a
    if t > dur - r:
        return max(0.0, (dur - t) / r)
    return 1.0


def tone(dur, f0, f1=None, kind='sq', vol=0.5, a=0.005, r=0.05, decay=0.0):
    n = int(dur * SR)
    f1 = f1 or f0
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = f0 * (f1 / f0) ** (t / dur)
        ph += f / SR
        v = osc(kind, ph) * vol * env(t, dur, a, r)
        if decay:
            v *= math.exp(-decay * t)
        out.append(v)
    return out


def noise(dur, vol=0.5, lp=0.5, seed=1, a=0.005, r=0.05, decay=0.0):
    rnd = random.Random(seed)
    out, y = [], 0.0
    n = int(dur * SR)
    for i in range(n):
        t = i / SR
        y += (rnd.uniform(-1, 1) - y) * lp
        v = y * vol * env(t, dur, a, r)
        if decay:
            v *= math.exp(-decay * t)
        out.append(v)
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, x in enumerate(p):
            out[i] += x
    return out


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def silence(d):
    return [0.0] * int(d * SR)


def note_hz(n):
    """'C4' 같은 이름 → 주파수"""
    names = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    k = names[n[0]]
    i = 1
    if n[i] == '#':
        k += 1; i += 1
    elif n[i] == 'b':
        k -= 1; i += 1
    octave = int(n[i:])
    return 440.0 * 2 ** ((k + (octave - 4) * 12) / 12)


# ───────────── 효과음 ─────────────

def engine():
    # 끊김 없이 이어지도록 정수 주기. 기본 90Hz 톱니 + 반 주파수 네모 + 약한 떨림
    f = 90.0
    cycles = 45
    n = int(round(cycles / f * SR))
    out = []
    for i in range(n):
        ph = i * cycles / n
        v = 0.5 * osc('saw', ph) + 0.35 * osc('sq', ph * 0.5) + 0.2 * osc('sin', ph * 2)
        v *= 0.8 + 0.2 * math.sin(2 * math.pi * i * 5 / n)
        out.append(v)
    return out


def _squeal(n, seed, f0=1150.0, sweep=None):
    """타이어 끼익: 1kHz 언저리 떨리는 음 몇 개 + 좁은 대역 잡음. sweep(t)→배율"""
    rnd = random.Random(seed)
    out = []
    ph1 = ph2 = ph3 = 0.0
    walk = 0.0
    lo1 = lo2 = 0.0
    flutter_ph = 0.0
    for i in range(n):
        t = i / SR
        walk += (rnd.uniform(-1, 1) * 0.004 - walk * 0.002)
        jit = 1.0 + walk + 0.012 * math.sin(2 * math.pi * 7.3 * t) + rnd.uniform(-0.004, 0.004)
        f = f0 * jit * (sweep(t) if sweep else 1.0)
        ph1 += f / SR
        ph2 += f * 1.49 / SR
        ph3 += f * 2.13 / SR
        flutter_ph += (31.0 + 9.0 * math.sin(2 * math.pi * 0.9 * t)) / SR
        flutter = 0.75 + 0.25 * math.sin(2 * math.pi * flutter_ph)
        tonal = math.sin(2 * math.pi * ph1) + 0.45 * math.sin(2 * math.pi * ph2) + 0.25 * osc('tri', ph3)
        x = rnd.uniform(-1, 1)
        lo1 += (x - lo1) * 0.55
        lo2 += (lo1 - lo2) * 0.18
        band = (lo1 - lo2) * 1.6          # 대역 잡음 (고음 쪽 쉬익)
        out.append((tonal * 0.55 * flutter + band * 0.35))
    return out


def skid():
    """드리프트 중 계속 나는 끼익 (이어 붙여 반복)"""
    n = int(1.4 * SR)
    out = _squeal(n, 5)
    m = int(0.08 * SR)
    for i in range(m):
        k = i / m
        out[i] = out[i] * k + out[n - m + i] * (1 - k)
    return out[: n - m]


def screech():
    """드리프트를 거는 순간 끼이익 한 번 (높게 시작해 내려옴)"""
    dur = 0.55
    n = int(dur * SR)
    raw = _squeal(n, 11, 1250.0, lambda t: 1.25 - 0.25 * min(1.0, t / 0.18))
    return [x * env(i / SR, dur, 0.008, 0.25) * (1.0 if i / SR < 0.15 else 0.75) for i, x in enumerate(raw)]


def boost():
    return mix(noise(0.9, 0.7, 0.25, 3, 0.02, 0.4), tone(0.9, 180, 640, 'saw', 0.25, 0.01, 0.4))


def mini():
    return mix(tone(0.28, 500, 1400, 'sq', 0.25, 0.005, 0.12), noise(0.28, 0.3, 0.5, 4, 0.005, 0.15))


def gain():
    return seq(tone(0.09, note_hz('E5'), kind='pul', vol=0.35), tone(0.18, note_hz('B5'), kind='pul', vol=0.35, r=0.12))


def beep():
    return tone(0.22, note_hz('A4'), kind='sq', vol=0.4, r=0.08)


def go():
    return tone(0.6, note_hz('A5'), kind='sq', vol=0.4, r=0.3)


def coin():
    return seq(tone(0.06, note_hz('B5'), kind='sq', vol=0.3), tone(0.16, note_hz('E6'), kind='sq', vol=0.3, r=0.12))


def bump():
    return mix(noise(0.25, 0.9, 0.08, 9, 0.002, 0.2, decay=10), tone(0.2, 120, 50, 'sin', 0.6, 0.002, 0.15))


def lap():
    return seq(*[tone(0.1, note_hz(n), kind='pul', vol=0.3, r=0.06) for n in ['C5', 'E5', 'G5']], tone(0.25, note_hz('C6'), kind='pul', vol=0.3, r=0.2))


def finish():
    notes = [('G4', 0.12), ('C5', 0.12), ('E5', 0.12), ('G5', 0.3), ('E5', 0.12), ('G5', 0.6)]
    mel = seq(*[tone(d, note_hz(n), kind='pul', vol=0.3, r=0.05) for n, d in notes])
    bass = seq(*[tone(d, note_hz(n) / 4, kind='tri', vol=0.4, r=0.05) for n, d in notes])
    return mix(mel, bass)


def click():
    return tone(0.05, 900, 600, 'sq', 0.25, 0.001, 0.03)


def tick():
    return tone(0.03, 1500, kind='sin', vol=0.2, a=0.001, r=0.02)


def buy():
    return seq(coin(), tone(0.08, note_hz('G6'), kind='sq', vol=0.25), tone(0.3, note_hz('C7'), kind='sq', vol=0.25, r=0.25))


def item():
    return seq(*[tone(0.05, note_hz(n), kind='pul', vol=0.28, r=0.03) for n in ['C6', 'E6', 'G6', 'C7']])


def throw():
    return mix(noise(0.3, 0.6, 0.35, 21, 0.01, 0.2), tone(0.3, 300, 900, 'tri', 0.2, 0.01, 0.2))


def hit():
    return seq(mix(noise(0.12, 0.8, 0.2, 23, 0.002, 0.1, decay=12), tone(0.12, 220, 110, 'sq', 0.35, 0.002, 0.08)),
               tone(0.5, 700, 180, 'tri', 0.25, 0.01, 0.3))


def shield():
    return mix(tone(0.45, 880, 1320, 'sin', 0.25, 0.01, 0.3), tone(0.45, 1320, 1760, 'sin', 0.15, 0.05, 0.3))


def nope():
    return seq(tone(0.1, 220, kind='sq', vol=0.3), tone(0.2, 165, kind='sq', vol=0.3, r=0.1))


# ───────────── 배경음 (새로 지은 곡) ─────────────

def render(bpm, bars, chords, melody, drums=True, lead='pul', bass_kind='tri', swing=0.0):
    """chords: 마디마다 화음 이름 목록(근음 기준), melody: (음 또는 None, 박 길이) 목록"""
    beat = 60.0 / bpm
    total = int(bars * 4 * beat * SR)
    out = [0.0] * total

    def add(start, part):
        s = int(start * SR)
        for i, x in enumerate(part):
            if s + i < total:
                out[s + i] += x

    # 베이스와 화음 (8분 쪼개기)
    for b in range(bars):
        root, kind = chords[b % len(chords)]
        r = note_hz(root)
        third = r * (2 ** ((3 if kind == 'm' else 4) / 12))
        fifth = r * (2 ** (7 / 12))
        for e in range(8):
            t = (b * 4 + e * 0.5) * beat
            bf = r / 2 if e % 2 == 0 else fifth / 2
            add(t, tone(beat * 0.45, bf, kind=bass_kind, vol=0.32, r=0.03))
            if e % 2 == 1:
                for f in (r * 2, third * 2, fifth * 2):
                    add(t, tone(beat * 0.3, f, kind='sq', vol=0.05, r=0.05))
    # 멜로디
    t = 0.0
    while t < bars * 4:
        for n, d in melody:
            if t >= bars * 4:
                break
            if n:
                add(t * beat, tone(d * beat * 0.92, note_hz(n), kind=lead, vol=0.18, a=0.01, r=0.04))
            t += d
    # 북
    if drums:
        for q in range(bars * 8):
            t = q * 0.5 * beat
            if q % 4 == 0:
                add(t, tone(0.12, 140, 45, 'sin', 0.5, 0.001, 0.08))
            if q % 4 == 2:
                add(t, noise(0.12, 0.35, 0.7, q, 0.001, 0.08, decay=20))
            add(t, noise(0.03, 0.08, 0.9, q + 100, 0.001, 0.02))
    return out


def title_music():
    chords = [('F4', ''), ('C4', ''), ('D4', 'm'), ('A#3', ''), ('F4', ''), ('C4', ''), ('A#3', ''), ('C4', '')]
    mel = [('A5', 1), ('G5', 0.5), ('F5', 0.5), ('G5', 1), ('C5', 1),
           ('D5', 0.5), ('E5', 0.5), ('F5', 1), ('A5', 1), ('G5', 1),
           ('F5', 1), ('D5', 1), ('F5', 0.5), ('G5', 0.5), ('A5', 1),
           ('A#5', 1), ('A5', 0.5), ('G5', 0.5), ('F5', 1), (None, 1),
           ('A5', 1), ('C6', 1), ('A#5', 0.5), ('A5', 0.5), ('G5', 1),
           ('F5', 1), ('G5', 1), ('A5', 1), ('F5', 1),
           ('D5', 1), ('F5', 1), ('G5', 1), ('A#5', 1),
           ('A5', 1.5), ('G5', 0.5), ('F5', 2)]
    return render(112, 8, chords, mel, drums=True, lead='tri')


def race_music():
    chords = [('A3', 'm'), ('F3', ''), ('C4', ''), ('G3', ''), ('A3', 'm'), ('F3', ''), ('G3', ''), ('E3', '')]
    mel = [('E5', 0.5), ('A5', 0.5), ('B5', 0.5), ('C6', 0.5), ('B5', 0.5), ('A5', 0.5), ('E5', 1),
           ('F5', 0.5), ('A5', 0.5), ('C6', 1), ('A5', 0.5), ('G5', 0.5), ('F5', 1),
           ('E5', 0.5), ('G5', 0.5), ('C6', 0.5), ('E6', 0.5), ('D6', 1), ('C6', 1),
           ('B5', 0.5), ('D6', 0.5), ('G5', 1), ('B5', 1), (None, 1),
           ('A5', 0.5), ('C6', 0.5), ('E6', 1), ('D6', 0.5), ('C6', 0.5), ('B5', 1),
           ('A5', 0.5), ('F5', 0.5), ('A5', 1), ('C6', 1), ('A5', 1),
           ('B5', 0.5), ('D6', 0.5), ('B5', 0.5), ('G5', 0.5), ('D6', 1), ('B5', 1),
           ('G#5', 1), ('B5', 1), ('E6', 1.5), (None, 0.5)]
    return render(150, 8, chords, mel, drums=True, lead='pul')


def parse_mel(text):
    """'E5:.5 -:1 G5:1/3' → [(음 또는 None, 박)]"""
    out = []
    for tok in text.split():
        n, d = tok.split(':')
        if '/' in d:
            x, y = d.split('/')
            b = float(x or 1) / float(y)
        else:
            b = float(d)
        out.append((None if n == '-' else n, b))
    return out


def song(bpm, sections, lead='pul', lead_vol=0.17, bass_vol=0.3, seed=1):
    """구역마다 {bars, melody, chords(마디마다 'E2 E3 G3 B3'), drums(16칸: k 큰북, K 큰북+심벌, s 작은북, h 하이햇), arp, pump}
    pump=True면 베이스가 8분으로 근음·옥타브를 번갈아 친다(달리는 느낌)."""
    beat = 60.0 / bpm
    total_beats = sum(sec['bars'] * 4 for sec in sections)
    total = int(total_beats * beat * SR) + SR
    out = [0.0] * total
    rnd = random.Random(seed)

    def add(start_beat, part, gain=1.0):
        s0 = int(start_beat * beat * SR)
        for i, x in enumerate(part):
            j = s0 + i
            if j < total:
                out[j] += x * gain

    pos = 0.0
    for sec in sections:
        bars = sec['bars']
        chords = [c.split() for c in sec['chords']]
        for b in range(bars):
            ch = chords[b % len(chords)]
            root = note_hz(ch[0])
            bar0 = pos + b * 4
            # 베이스
            if sec.get('pump', True):
                for e in range(8):
                    f = root * (2 if e % 2 else 1)
                    add(bar0 + e * 0.5, tone(beat * 0.42, f, kind='sq' if e % 2 else 'tri', vol=bass_vol * (0.55 if e % 2 else 1.0), r=0.02))
            else:
                for e in range(4):
                    add(bar0 + e, tone(beat * 0.9, root, kind='tri', vol=bass_vol, r=0.05))
            # 화음 (뒷박 짧게)
            ups = [note_hz(n) for n in ch[1:]]
            for e in range(4):
                for f in ups:
                    add(bar0 + e + 0.5, tone(beat * 0.22, f, kind='sq', vol=0.035, r=0.03))
            # 아르페지오 (16분)
            if sec.get('arp'):
                tones = ups + [u * 2 for u in ups]
                for q in range(16):
                    add(bar0 + q * 0.25, tone(beat * 0.2, tones[q % len(tones)] * 2, kind='pul', vol=0.045, r=0.02))
            # 북 (16칸)
            pat = sec.get('drums', '')
            for q, c in enumerate(pat[:16]):
                t = bar0 + q * 0.25
                if c in 'kK':
                    add(t, tone(0.11, 150, 42, 'sin', 0.55, 0.001, 0.07))
                if c == 'K':
                    add(t, noise(0.5, 0.2, 0.9, rnd.randint(0, 9999), 0.001, 0.4, decay=5))
                if c == 's':
                    add(t, mix(noise(0.13, 0.38, 0.75, rnd.randint(0, 9999), 0.001, 0.09, decay=18), tone(0.08, 190, 150, 'tri', 0.18, 0.001, 0.06)))
                if c in 'hks.' and q % 2 == 0:
                    add(t, noise(0.025, 0.05, 0.95, rnd.randint(0, 9999), 0.001, 0.02))
                if c == 'h':
                    add(t, noise(0.04, 0.09, 0.95, rnd.randint(0, 9999), 0.001, 0.03))
        # 멜로디
        t = pos
        for n, d in parse_mel(sec['melody']):
            if n:
                add(t, tone(d * beat * 0.9, note_hz(n), kind=lead, vol=lead_vol, a=0.006, r=0.03))
                # 살짝 늦은 메아리
                add(t + 0.75, tone(d * beat * 0.8, note_hz(n), kind=lead, vol=lead_vol * 0.22, a=0.006, r=0.03))
            t += d
        pos += bars * 4
    return out[: int(total_beats * beat * SR)]


def rush_music():
    """긴박한 경주 곡: E단조 8비트 록, 176 BPM (새로 지은 곡)"""
    E, C, D, B, A, G = 'E2 E4 G4 B4', 'C3 C4 E4 G4', 'D3 D4 F#4 A4', 'B2 B3 D#4 F#4', 'A2 A3 C4 E4', 'G2 G3 B3 D4'
    secs = [
        {'bars': 4, 'chords': [E, E, C, D], 'drums': 'k.k.s.k.k.k.s.ss', 'pump': True,
         'melody': 'E5:.5 E5:.5 -:.5 E5:.5 -:.5 E5:.5 G5:.5 A5:.5 B5:1 -:1 B5:.5 A5:.5 G5:.5 F#5:.5 G5:.5 -:.5 G5:.5 E5:.5 C6:1 B5:1 A5:.5 B5:.5 A5:.5 G5:.5 F#5:1 D5:1'},
        {'bars': 8, 'chords': [E, C, D, B, E, C, A, B], 'drums': 'k.h.s.h.k.k.s.h.',
         'melody': 'E5:.5 B4:.5 E5:.5 G5:.5 F#5:.5 E5:.5 D5:.5 E5:.5 C5:.5 E5:.5 G5:.5 E5:.5 A5:1 G5:1 D5:.5 F#5:.5 A5:.5 F#5:.5 B5:1 A5:1 F#5:.5 D#5:.5 B4:.5 D#5:.5 F#5:2 '
                   'E5:.5 B4:.5 E5:.5 G5:.5 B5:.5 A5:.5 G5:.5 F#5:.5 G5:.5 E5:.5 C5:.5 E5:.5 G5:1 A5:1 A5:.5 C6:.5 B5:.5 A5:.5 E5:1 C5:1 B4:.5 D#5:.5 F#5:.5 A5:.5 B5:2'},
        {'bars': 8, 'chords': [A, B, C, D, A, B, C, D], 'drums': 'k.h.s.hkk.h.s.hs',
         'melody': 'A5:1 E5:.5 A5:.5 C6:1 B5:1 B5:1 F#5:.5 B5:.5 D#6:1 B5:1 C6:.5 B5:.5 A5:.5 G5:.5 E5:1 G5:1 F#5:.5 G5:.5 A5:.5 B5:.5 D6:2 '
                   'A5:.25 A5:.25 C6:.5 A5:.5 E5:.5 A5:1 B5:1 B5:.25 B5:.25 D#6:.5 B5:.5 F#5:.5 B5:1 A5:1 G5:.5 A5:.5 B5:.5 C6:.5 D6:1 E6:1 F#6:2 D#6:2'},
        {'bars': 8, 'chords': [E, C, G, D, E, C, B, B], 'drums': 'kshskshskshsKshs', 'arp': True,
         'melody': 'E6:1 B5:.5 G5:.5 E6:1 D6:1 C6:1 G5:.5 E5:.5 C6:1 B5:1 B5:1 G5:.5 D5:.5 B5:1 A5:.5 G5:.5 A5:1 F#5:.5 D5:.5 A5:2 '
                   'E6:1 B5:.5 G5:.5 E6:1 F#6:1 G6:1 E6:.5 C6:.5 G5:1 C6:1 B5:.5 C6:.5 B5:.5 A5:.5 F#5:1 D#5:1 B5:2 F#5:1 D#5:1'},
        {'bars': 8, 'chords': [E, C, G, D, E, C, B, E], 'drums': 'kshskshskshsKshs', 'arp': True,
         'melody': 'E6:1 B5:.5 G5:.5 E6:1 D6:1 C6:1 G5:.5 E5:.5 C6:1 B5:1 B5:1 G5:.5 D5:.5 B5:1 A5:.5 G5:.5 A5:1 F#5:.5 D5:.5 A5:2 '
                   'E6:1 B5:.5 G5:.5 E6:1 F#6:1 G6:1 E6:.5 C6:.5 G5:1 C6:1 B5:.5 C6:.5 B5:.5 A5:.5 F#5:1 D#5:1 E6:2 B5:1 G5:1'},
    ]
    return song(176, secs, lead='pul', seed=4)


def main():
    sfx = {'engine': engine, 'skid': skid, 'screech': screech, 'boost': boost, 'mini': mini, 'gain': gain, 'beep': beep, 'go': go,
           'coin': coin, 'bump': bump, 'lap': lap, 'finish': finish, 'click': click, 'tick': tick, 'buy': buy, 'nope': nope, 'item': item, 'throw': throw, 'hit': hit, 'shield': shield}
    for name, fn in sfx.items():
        write(os.path.join(ROOT, 'sfx', name + '.wav'), fn())
    write(os.path.join(ROOT, 'music', 'title.wav'), title_music(), norm=0.7)
    write(os.path.join(ROOT, 'music', 'race.wav'), race_music(), norm=0.7)
    write(os.path.join(ROOT, 'music', 'rush.wav'), rush_music(), norm=0.72)
    print('소리 %d개 + 곡 3개' % len(sfx))


if __name__ == '__main__':
    main()

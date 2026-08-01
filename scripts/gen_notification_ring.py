"""Generate a Telegram-style two-tone marimba notification sound (WAV)."""
import math
import struct
import wave

SAMPLE_RATE = 44100
DURATION = 0.85


def marimba_note(freq, start, length, amp):
    """Render one marimba-like note: fundamental + soft harmonics, fast decay."""
    samples = [0.0] * int(SAMPLE_RATE * DURATION)
    n_start = int(start * SAMPLE_RATE)
    n_len = int(length * SAMPLE_RATE)
    for i in range(n_len):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 9.0)
        # attack softening for the first 3ms
        attack = min(1.0, t / 0.003)
        value = (
            math.sin(2 * math.pi * freq * t)
            + 0.35 * math.sin(2 * math.pi * freq * 4.0 * t) * math.exp(-t * 22)
            + 0.18 * math.sin(2 * math.pi * freq * 9.2 * t) * math.exp(-t * 40)
        )
        idx = n_start + i
        if idx < len(samples):
            samples[idx] += amp * env * attack * value
    return samples


def mix(*tracks):
    out = [0.0] * int(SAMPLE_RATE * DURATION)
    for track in tracks:
        for i, v in enumerate(track):
            out[i] += v
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak * 0.85 for v in out]


def main():
    # Telegram-like "ding-dong": E6 then C#6, slightly overlapping
    note1 = marimba_note(1318.51, 0.0, 0.6, 1.0)   # E6
    note2 = marimba_note(1108.73, 0.13, 0.7, 0.9)  # C#6
    data = mix(note1, note2)

    frames = b''.join(
        struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767)) for v in data
    )
    for path in [
        'openim_common/assets/audio/notification_ring.wav',
        'android/app/src/main/res/raw/notification_ring.wav',
        'ios/Runner/notification_ring.wav',
    ]:
        with wave.open(path, 'wb') as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(SAMPLE_RATE)
            f.writeframes(frames)
        print(f'written: {path}')


if __name__ == '__main__':
    main()

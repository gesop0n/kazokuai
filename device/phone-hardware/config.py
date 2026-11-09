"""Change hardware settings here. GPIO numbers are BCM, not header pins."""
INPUT_DEVICE = 1
OUTPUT_DEVICE = 1
AUDIO_RATE = None  # None: use output device's native sample rate
MIC_CHANNEL = 0
SPEAKER_GAIN = 0.5
SPEAKER_PEAK_LIMIT = 0.1
ROW_GPIO = (17, 27, 22, 23)
COL_GPIO = (24, 25, 4)
# Only 5 at R2/C2 has been confirmed. Verify other keys on your telephone.
KEYS = (("1", "2", "3"), ("4", "5", "6"), ("7", "8", "9"), ("*", "0", "#"))
RINGER_GPIO = 18
HOOK_GPIO = 5
LIFTED_WHEN_CLOSED = True  # False if contacts open when handset is lifted
DEBOUNCE_SECONDS = 0.05

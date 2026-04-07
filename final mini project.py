import cv2
import numpy as np
import matplotlib.pyplot as plt
import serial
import time
import pyaudio
import threading

# SHARED STATE
emergency_active    = False
emergency_timer     = 0
siren_ratio         = 0.0
siren_detected_once = False
start_listening     = False

# SIREN DETECTION PARAMETERS
SAMPLE_RATE      = 44100
CHUNK            = 512        
SIREN_LOW_HZ     = 700
SIREN_HIGH_HZ    = 2500
SIREN_THRESHOLD  = 0.7
SIREN_HOLD_SEC   = 20

# SIREN DETECTION THREAD
def detect_siren():
    global emergency_active, emergency_timer, siren_ratio
    global siren_detected_once, start_listening

    pa     = pyaudio.PyAudio()
    stream = pa.open(
        format=pyaudio.paFloat32,
        channels=1,
        rate=SAMPLE_RATE,
        input=True,
        frames_per_buffer=CHUNK
    )

    while True:
        try:
            # Wait until LED is ON before listening
            if not start_listening:
                time.sleep(0.01)
                continue

            # Already detected — wait for hold to expire
            if siren_detected_once:
                if time.time() - emergency_timer > SIREN_HOLD_SEC:
                    emergency_active    = False
                    siren_detected_once = False
                    print("\nEmergency cleared")
                time.sleep(0.05)
                continue

            # Active listening
            data     = np.frombuffer(
                           stream.read(CHUNK, exception_on_overflow=False),
                           dtype=np.float32)
            fft_vals = np.abs(np.fft.rfft(data))
            freqs    = np.fft.rfftfreq(len(data), 1.0 / SAMPLE_RATE)

            siren_band   = fft_vals[(freqs >= SIREN_LOW_HZ) &
                                    (freqs <= SIREN_HIGH_HZ)]
            total_energy = np.sum(fft_vals)
            siren_ratio  = np.sum(siren_band) / (total_energy + 1e-6)

            # Detected — set flag immediately
            # Main thread handles serial write instantly
            if siren_ratio > SIREN_THRESHOLD:
                if not siren_detected_once:
                    print(f"\nSIREN DETECTED! "
                          f"(confidence={siren_ratio:.2f})")
                emergency_active    = True
                emergency_timer     = time.time()
                siren_detected_once = True

        except Exception as e:
            print(f"Audio error: {e}")
            break

    stream.stop_stream()
    stream.close()
    pa.terminate()

# =============================================================
# 1. START SIREN THREAD
siren_thread = threading.Thread(target=detect_siren, daemon=True)
siren_thread.start()
time.sleep(1)

# 2. LOAD AND ANALYSE IMAGE
print("Analysing traffic image...")

img = cv2.imread("traffic_high.jpg")
if img is None:
    print("Image not found")
    exit()

img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
gray    = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
blur    = cv2.GaussianBlur(gray, (5, 5), 0)
sobelx  = cv2.Sobel(blur, cv2.CV_64F, 1, 0, ksize=3)
sobely  = cv2.Sobel(blur, cv2.CV_64F, 0, 1, ksize=3)
sobel   = np.uint8(np.clip(np.sqrt(sobelx**2 + sobely**2), 0, 255))
_, binary = cv2.threshold(sobel, 50, 255, cv2.THRESH_BINARY)

height, width = binary.shape
mask    = np.zeros_like(binary)
polygon = np.array([[
    (int(width * 0.25), height),
    (int(width * 1.00), height),
    (int(width * 0.50), int(height * 0.40)),
    (int(width * 0.45), int(height * 0.40))
]])
cv2.fillPoly(mask, polygon, 255)
roi     = cv2.bitwise_and(binary, mask)
density = np.sum(roi == 255) / roi.size

print(f"Image density          : {density:.4f}")

# 3. TRAFFIC CLASSIFICATION
if density < 0.05:
    traffic      = "LOW TRAFFIC"
    traffic_byte = b'2'
    wait_time    = 15
elif density < 0.08:
    traffic      = "MEDIUM TRAFFIC"
    traffic_byte = b'1'
    wait_time    = 10
else:
    traffic      = "HIGH TRAFFIC"
    traffic_byte = b'0'
    wait_time    = 5

print(f"Traffic classification : {traffic}")
print(f"Red light duration     : {wait_time}s")

# 4. SEND TRAFFIC BYTE → LED ON → LISTEN FOR SIREN
try:
    ser = serial.Serial('COM6', 9600, timeout=1)
    time.sleep(2)

    # STEP 1 — Send traffic byte, LED turns ON
    ser.write(traffic_byte)
    ser.flush()
    print(f"\nSTEP 1 - Sent {traffic_byte} to FPGA")
    print(f"         LED ON - Red light started ({wait_time}s)")

    # Enable mic exactly when LED turns ON
    start_listening = True
    print(f"\nSTEP 2 - Microphone ON - monitoring for ambulance...\n")

    listen_start   = time.time()
    emergency_sent = False

    while time.time() - listen_start < wait_time:
        remaining = wait_time - (time.time() - listen_start)

        # ── Check siren FIRST before anything else ────────────
        # This is checked every loop iteration with no delay
        if emergency_active and not emergency_sent:
            # Send b'3' IMMEDIATELY — no sleep before this
            ser.write(b'3')
            ser.flush()
            emergency_sent = True
            print(f"\nAmbulance at {remaining:.1f}s remaining!")
            print(f"b'3' sent instantly - Timer set to 0")
            print(f"Red light OFF - Green signal ON")
            break   # exit loop immediately

        # Status display
        print(f"  Countdown : {remaining:4.1f}s"
              f"  | Ratio : {siren_ratio:.3f}"
              f"{'  *** SIREN! ***' if emergency_active else ''}",
              end='\r')

        # Small sleep AFTER the siren check
        time.sleep(0.05)   # 50ms — faster than before (was 100ms)

    # Stop listening after countdown ends
    start_listening = False
    print()

    # Final state
    if emergency_sent:
        display_label = "AMBULANCE DETECTED"
        display_color = 'red'
        print(f"\nResult : Emergency override -ambulance")
    else:
        display_label = traffic + " | RED " + str(wait_time) + "s | Done"
        display_color = ('green'  if traffic == "LOW TRAFFIC"    else
                         'orange' if traffic == "MEDIUM TRAFFIC" else
                         'darkred')
        print(f"\nResult : {traffic} - Red light completed normally")

    ser.close()

except serial.SerialException as e:
    print(f"Serial error: {e}")
    display_label = traffic
    display_color = 'black'
    emergency_sent = False

# 5. DISPLAY RESULTS
fig = plt.figure(figsize=(12, 6))

plt.subplot(2, 3, 1)
plt.imshow(img_rgb)
plt.title("Original Image")
plt.axis("off")

plt.subplot(2, 3, 2)
plt.imshow(gray, cmap='gray')
plt.title("Grayscale")
plt.axis("off")

plt.subplot(2, 3, 3)
plt.imshow(blur, cmap='gray')
plt.title("Gaussian Blur")
plt.axis("off")

plt.subplot(2, 3, 4)
plt.imshow(sobel, cmap='gray')
plt.title("Sobel Edge")
plt.axis("off")

plt.subplot(2, 3, 5)
plt.imshow(binary, cmap='gray')
plt.title("Threshold Edge")
plt.axis("off")

plt.subplot(2, 3, 6)
plt.imshow(roi, cmap='gray')
plt.title("ROI  |  Density: " + f"{density:.4f}")
plt.axis("off")

if emergency_sent:
    title_text = "EMERGENCY OVERRIDE  |  " + display_label
else:
    title_text = display_label

plt.suptitle(
    title_text,
    fontsize=16,
    fontweight='bold',
    color=display_color
)

plt.tight_layout()
plt.show()

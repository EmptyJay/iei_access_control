#!/usr/bin/env python3
"""
Buzz the KY-006 passive piezo on GPIO 17 (Pin 11).

Usage:
  buzzer.py <seconds>  — single tone for given duration
  buzzer.py loop       — periodic beeps (0.2s on / 0.8s off) until SIGTERM
  buzzer.py fast       — fast high-pitched beeps (0.1s on / 0.2s off) until SIGTERM
"""
import signal
import sys
import time
import RPi.GPIO as GPIO

BUZZER_PIN = 17
FREQUENCY  = 1000  # Hz

GPIO.setmode(GPIO.BCM)
GPIO.setup(BUZZER_PIN, GPIO.OUT)
pwm = GPIO.PWM(BUZZER_PIN, FREQUENCY)

def stop(signum=None, frame=None):
    pwm.stop()
    GPIO.cleanup()
    sys.exit(0)

signal.signal(signal.SIGTERM, stop)

try:
    if len(sys.argv) > 1 and sys.argv[1] == "loop":
        while True:
            pwm.start(50)
            time.sleep(0.2)
            pwm.stop()
            time.sleep(0.8)
    elif len(sys.argv) > 1 and sys.argv[1] == "fast":
        pwm.ChangeFrequency(2000)
        while True:
            pwm.start(50)
            time.sleep(0.1)
            pwm.stop()
            time.sleep(0.2)
    else:
        duration = float(sys.argv[1]) if len(sys.argv) > 1 else 0.5
        pwm.start(50)
        time.sleep(duration)
        pwm.stop()
finally:
    GPIO.cleanup()

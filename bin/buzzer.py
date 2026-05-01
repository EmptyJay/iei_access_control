#!/usr/bin/env python3
"""Buzz the KY-006 passive piezo on GPIO 12 for a given duration (seconds)."""
import sys
import time
from gpiozero import PWMOutputDevice

GPIO_PIN  = 12    # Physical pin 32 — hardware PWM0
FREQUENCY = 1000  # Hz

duration = float(sys.argv[1]) if len(sys.argv) > 1 else 0.5
buzzer = PWMOutputDevice(GPIO_PIN, frequency=FREQUENCY)
buzzer.value = 0.5  # 50% duty cycle
time.sleep(duration)
buzzer.off()

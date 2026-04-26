# Raspberry Pi → IEI Max3 Controller Test Plan

**Purpose:** Step-by-step verification of serial communication, user management, and web UI actions against the real door controller.  
**Hardware:** Raspberry Pi + USB-to-RS485 adapter → IEI Max3 v2

> **All commands on the Pi must be run from `/opt/iei` with `RAILS_ENV=production` set.**  
> The development/test gems (including `debug`) are not installed in the production bundle.  
> Shortcut — add to your shell profile on the Pi:
> ```bash
> alias iei='cd /opt/iei && RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0'
> ```
> Then you can run e.g. `iei bin/rake max3:status`.

---

## Phase 1 — Environment

**Goal:** confirm the Pi can see the RS-485 adapter and the app is deployed.

- [ ] Plug in the USB-to-RS485 adapter. Run `ls /dev/tty*` and confirm `/dev/ttyUSB0` (or similar) appears.
- [ ] Check permissions: `ls -l /dev/ttyUSB0`. If the service user lacks read+write, run `sudo usermod -aG dialout <user>` and restart the service.
- [ ] Deploy: push latest code to GitHub, SSH to Pi, run `./bin/deploy`. Confirm it finishes without error (migrations run, service restarts).
- [ ] Check service is up: `systemctl status iei` → should show `active (running)`.

**Pass:** service is running, `/dev/ttyUSB0` exists and is accessible.

---

## Phase 2 — Handshake

**Goal:** confirm two-way serial communication with the controller.

```bash
RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0 bin/rails runner "Max3Session.open { |s| puts 'OK' }"
```

Or:

```bash
RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0 bin/rake max3:status
```

**What to watch for:**

| Symptom | Likely cause |
|---------|-------------|
| Read timeout | Wiring problem — A/B swapped, bad termination, wrong port |
| CRC mismatch | Baud rate or framing mismatch — confirm 19200 8N1 |
| `"OK"` / status bytes printed | Success |

**Pass:** no exception, handshake completes, controller status bytes are logged.

---

## Phase 3 — Read-Only Operations

**Goal:** exercise the controller without modifying any user data.

### 3a. Peek event log (no pointer advance)

```bash
RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0 bin/rails runner "Max3Session.open { |s| s.peek_event_log }"
```

Expected: prints log page hex lines, or "No unread events". Nothing written to DB.

**Pass:** no errors; TX/RX hex in log matches expected packet format.

---

## Phase 3.5 — Force-Clear the Controller

**Goal:** wipe any existing Hub Manager users from the controller hardware before testing, so there are no slot conflicts.

Run this before Phase 4 any time the controller may have users the app doesn't know about (e.g. fresh setup, after Hub Manager was last used).

```bash
RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0 bin/rake max3:force_clear
```

This walks slots 3–2000 and sends a delete packet for every one regardless of DB contents. Takes ~30–60 seconds. Slots 1 and 2 (master users) are never touched.

Also available as the **Force Clear** button in the dashboard Danger Zone.

**Pass:** completes without error; controller now has no regular users.

---

## Phase 4 — Single User Add / Delete

**Goal:** verify `add_user_packet` and `delete_user_packet` are accepted by the controller.

Use your own badge (known site code and card number) so you can physically test access.

- [ ] **Force-clear first** (Phase 3.5) to ensure no leftover Hub Manager users interfere.
- [ ] **Create a test user** in the web UI. Set active = true.
- [ ] **Sync:**
  ```bash
  RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0 bin/rake max3:sync
  ```
  Confirm the add_user packet is ACKed in log output.
- [ ] **Badge the door** → expected: access granted.
- [ ] **Deactivate** the test user in the UI, sync again.
- [ ] **Badge the door** → expected: access denied.
- [ ] **Fetch event log:**
  ```bash
  RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0 bin/rake max3:fetch_log
  ```
  Confirm grant and denial events appear in the web UI under Access Events with correct timestamps.

**Pass:** badge grants/denies match controller state; events appear in DB.

---

## Phase 5 — Rolling Counter Integrity

**Goal:** confirm the counter doesn't collide across multiple syncs.

- [ ] Add and re-sync the same user three times (deactivate → activate → deactivate → activate).
- [ ] After each add, verify in the TX log that the counter increments correctly and the controller ACKs.
- [ ] Badge after each sync to confirm the write actually took effect.

A counter collision would cause the controller to silently reject the write — no ACK error, but the badge won't work.

**Pass:** counter increments monotonically across sessions; each re-add produces a working badge.

---

## Phase 6 — Bulk Operations via Web UI

Work through each dashboard action in order of increasing destructiveness.

| Step | Action | Pre-condition | Expected outcome |
|------|--------|--------------|-----------------|
| 6a | Sync (pending users) | ≥1 active user marked unsynced | User added; badge works |
| 6b | Lockdown | Mix of standard + officer users synced | Standard badges denied; officer badge still works |
| 6c | Restore | Post-lockdown state | Standard users re-added; all badges work |
| 6d | Clear All | All users synced | Removes slots the app knows about; all users marked unsynced |
| 6e | Force Clear | Any state | Walks all 1998 slots; controller fully empty; all users marked unsynced |
| 6f | Sync (after clear) | All users unsynced, active | All re-added; all badges work |

**Note for 6b/6c:** requires at least one officer-tier user with a physical badge on hand to verify officer access is preserved during lockdown.

**Pass:** each action produces the correct physical result at the door.

---

## Phase 7 — Automated Log Import

If a cron job or systemd timer is configured for log fetching:

- [ ] Badge in (generates a grant event).
- [ ] Wait for the cron interval to fire.
- [ ] Confirm the event appears in Access Events with the correct member name and timestamp.

**Pass:** events are imported automatically without manual rake invocation.

---

## Things to Watch For

**Slot conflicts with existing Hub Manager data**  
If the controller already has users programmed by Hub Manager, run a force-clear before Phase 4:
```bash
RAILS_ENV=production MAX3_PORT=/dev/ttyUSB0 bin/rake max3:force_clear
```
Use `force_clear` (not `clear_users`) when the DB is empty or out of sync with the controller — it walks all slots unconditionally rather than relying on what the app knows.

**RS-485 half-duplex echo**  
Some USB adapters echo TX bytes back on RX. You'll see it immediately — the "response" packet will match the sent packet exactly. If this happens, a small drain/flush after `send_raw` is needed.

**Termination resistor**  
If you get intermittent timeouts or CRC errors, add a 120Ω resistor across A/B at the controller end.

**Counter seed after DB reset**  
The rolling counter is stored in the `settings` table. If you reset the DB, the counter resets too — this is fine since the controller has no memory of previous counter values. The counter only needs to be unique within your session sequence.

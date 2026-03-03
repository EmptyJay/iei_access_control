# IEI Max3 / prox.pad plus — Serial Protocol Specification

**Reverse engineered:** February 24, 2026  
**Hardware:** IEI Max3 v2 door controller  
**Serial:** RS-485, 19200 baud, 8N1  
**Tool used:** HHD Device Monitoring Studio (USB-to-RS485 capture)  
**Purpose:** Replace Hub Manager Pro v8 with a custom Rails web application on Raspberry Pi

---

## 1. Physical Layer

- **Interface:** RS-485 (half-duplex)
- **Baud rate:** 19200
- **Frame:** 8N1 (8 data bits, no parity, 1 stop bit)
- **Connector:** USB-to-RS485 adapter on PC/Pi side
- **Controller address:** 2 (configured in Hub Manager)

---

## 2. Packet Structure

Every packet — both directions — follows this structure:

```
[HEADER 4 bytes] [LEN 1 byte] [PAYLOAD LEN bytes] [CRC_HI CRC_LO]
```

| Field | Value | Notes |
|-------|-------|-------|
| Header | `24 DB 02 00` | Fixed preamble — `24`=sync, `DB`=fixed, `02`=controller address, `00`=fixed |
| LEN | 1 byte | Number of payload bytes that follow |
| PAYLOAD | LEN bytes | First byte is always the command/response code |
| CRC | 2 bytes | CRC-CCITT, big-endian, covers LEN + PAYLOAD bytes |

### Example packet

```
24 DB 02 00 | 01 | 04 | 1A 1D
  header      len  cmd  crc
```

---

## 3. CRC Algorithm

**Algorithm:** CRC-CCITT  
**Polynomial:** 0x1021  
**Initial value:** 0x7B6D ← non-standard, custom to this controller  
**Calculated over:** [LEN byte] + [all PAYLOAD bytes]

```python
def crc16_ccitt(data, poly=0x1021, init=0x7B6D):
    crc = init
    for byte in data:
        crc ^= (byte << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ poly
            else:
                crc <<= 1
        crc &= 0xFFFF
    return crc

# Example: set_datetime command payload
data = [0x09, 0x28, 0x36, 0x50, 0x20, 0x03, 0x24, 0x02, 0x26, 0x00]
hi, lo = crc >> 8, crc & 0xFF
```

```ruby
def crc16_ccitt(data)
  crc = 0x7B6D
  data.each do |byte|
    crc ^= (byte << 8)
    8.times do
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1)
    end
    crc &= 0xFFFF
  end
  crc
end
```

---

## 4. Session Handshake

Every communication session begins with this fixed 4-packet exchange:

```
PC  → 24 DB 02 00 01 04 1A 1D
CTL → 24 DB 02 00 13 05 [18 status bytes] [CRC CRC]
PC  → 24 DB 02 00 01 34 2C 4E
CTL → 24 DB 02 00 04 35 01 00 00 BF B7
```

The second packet (status response, cmd `0x05`) contains 18 bytes of device info. The third and fourth packets (`0x34` / `0x35`) complete the handshake.

After the handshake, the controller is ready to receive commands.

---

## 5. Status Response (cmd 0x11 / 0x05)

The controller returns a 19-byte status packet in two contexts:
- As the second packet of the handshake (cmd `0x05`, 18 payload bytes)
- After log operations (cmd `0x11`, 18 payload bytes)

The `0x11` variant contains the event log read pointers:

```
Payload (18 bytes):
A1 92 80 D1 08 08 00 [log_start_hi] [log_start_lo] [log_end_hi] [log_end_lo]
[hour_hex] [min_hex] [day] [month] [year_2digit] 00 00
```

| Field | Description |
|-------|-------------|
| `log_start` | Address of first unread log page |
| `log_end` | Address of next write slot (stop reading here) |
| timestamp | Current controller time (plain hex, not BCD) |

When `log_start == log_end`, there are no new events to read.

After a log import, the controller advances `log_start` to `log_end`.

---

## 6. Commands — PC to Controller

### 6.1 Set Date/Time (0x28)

```
LEN: 09
Payload: 28 [sec] [min] [hour] [dow] [day] [month] [year_2digit] 00
```

All time fields are plain hexadecimal (not BCD).

| Field | Notes |
|-------|-------|
| sec, min, hour | 24-hour, e.g. 0x14 = 20 |
| dow | Day of week: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat |
| day, month | Calendar date |
| year | Last 2 digits, e.g. 0x26 = 2026 |

**Example:** 2026-02-24 20:50:36 (Tuesday)
```
28 36 50 20 03 24 02 26 00
```

---

### 6.2 Add / Update User (0x90)

```
LEN: 15 (21 decimal)
Payload (21 bytes):
[00] 90         command
[01] 00         fixed
[02] slot_hi    upper byte of slot number
[03] slot_lo    lower byte of slot number
[04] pin_flag   0x21 = no PIN, 0x31 = has PIN (not used in card-only setup)
[05] 84         fixed
[06] 00         fixed
[07] tz_index   access level / timezone index (01 for 24-Hour / ERC Members)
[08] 00         fixed
[09] 00         fixed
[10] 00         fixed
[11] 15         fixed
[12] counter    rolling counter, increments with each write (D0, D1, D2...)
[13] 0F         PIN byte 1 (0x0F when no PIN)
[14] FF         PIN byte 2 (0xFF when no PIN)
[15] FF         PIN byte 3 (0xFF when no PIN)
[16] 00         fixed
[17] 00         fixed
[18] card_b0    card data byte 0 (MSB)
[19] card_b1    card data byte 1
[20] card_b2    card data byte 2
[21] card_b3    card data byte 3 (LSB)
```

**Slot number** is 2 bytes big-endian. All real members use slots up to ~582 (0x0246). For slots ≤ 255, `slot_hi = 0x00`.

**Rolling counter** starts at 0xD0 and increments by 1 with each write to any user. It is global across all users, not per-user. The app must track the last value used.

**Access level index:** All ERC members use index `0x01` (24-Hour, all days). No other index is needed.

#### Card Data Encoding (26-bit HID Prox)

```python
def encode_card(site_code, card_number):
    raw = (site_code << 17) | (card_number << 1)
    return [(raw >> 24) & 0xFF, (raw >> 16) & 0xFF,
            (raw >> 8) & 0xFF, raw & 0xFF]
```

```ruby
def encode_card(site_code, card_number)
  raw = (site_code << 17) | (card_number << 1)
  [(raw >> 24) & 0xFF, (raw >> 16) & 0xFF, (raw >> 8) & 0xFF, raw & 0xFF]
end
```

**Examples:**
| Site | Card | Internal Value | Bytes |
|------|------|---------------|-------|
| 1 | 1 | 0006020002 | 06 02 00 02 |
| 1 | 2 | 0006020004 | 06 02 00 04 |
| 105 | 51770 | 0004D39475 | 04 D3 94 75 |
| 105 | 15193 | 0004D2EBB2 | (calculated) |

All real ERC members use site code **105**.

---

### 6.3 Delete User (0x93)

```
LEN: 03
Payload: 93 00 [slot_lo]
```

For slots ≤ 255, the format is always `93 00 [slot]`. For slots > 255 (not seen in real data), it would be `93 [slot_hi] [slot_lo]`.

Controller responds with ACK echoing the CRC of the delete command.

---

### 6.4 Write Timezone (0xB0)

```
LEN: 07
Payload: B0 [index] [days_mask] [hour_start] [min_start] [hour_stop] [min_stop]
```

**Days bitmask:**
| Bit | Day |
|-----|-----|
| 0 (0x01) | Sunday |
| 1 (0x02) | Monday |
| 2 (0x04) | Tuesday |
| 3 (0x08) | Wednesday |
| 4 (0x10) | Thursday |
| 5 (0x20) | Friday |
| 6 (0x40) | Saturday |
| 7 (0x80) | Holiday |

Times are plain hex (24-hour). 0x00 = midnight, 0x17 = 23:00.

**Examples:**
- 24 Hour (all days, midnight to midnight): `B0 01 FF 00 00 00 00`
- Mon–Fri 12AM–12AM: `B0 02 3E 00 00 00 00` (0x3E = 0b00111110)
- Mon/Wed/Fri/Hol 7AM–9PM: `B0 03 AA 07 00 21 00` (0xAA = 0b10101010)

For the app, only timezone index `0x01` (24 Hour) is used. It is the built-in default and does not need to be written.

---

### 6.5 Delete Timezone (0xB0 with FF payload)

```
LEN: 07
Payload: B0 [index] FF FF FF FF FF
```

Same command as write timezone but with all time/day fields set to `FF`. Only test timezones (index 02, 03) were ever deleted. Index 01 (24 Hour) cannot be deleted.

---

### 6.6 End Session (0xA0)

```
LEN: 01
Payload: A0
Full packet: 24 DB 02 00 01 A0 EF 73
```

Sent to close a session. Also used as a keep-alive prefix in the dashboard polling loop.

---

### 6.7 End Log Read (0xA5)

```
LEN: 01
Payload: A5
Full packet: 24 DB 02 00 01 A5 BF D6
```

Sent after reading all log pages to signal end of log import.

---

### 6.8 Read Log Page (0x0A)

```
LEN: 04
Payload: 0A [addr_hi] [addr_lo] 08
```

Reads one 8-byte log page from controller memory. The address increments by 8 for each successive page. The range to read comes from the status response log pointers.

---

### 6.9 Door Query (0x91)

```
LEN: 03
Payload: 91 00 [door_number]
Full packet (door 1): 24 DB 02 00 03 91 00 01 41 A4
```

Requests status and hardware info for the specified door. Used by Hub Manager's Info dialog. Not required for normal operation but useful for a health check / status page in the app.

Controller responds with cmd `0x92` (see Section 7.4).

---

## 7. Controller Responses

### 7.1 ACK (0x01)

```
LEN: 03
Payload: 01 [crc_hi] [crc_lo]
```

The two bytes echoed are the CRC of the command being acknowledged. Used to confirm receipt of: set_datetime, add user, delete user, write/delete timezone.

### 7.2 Handshake ACK (0x35)

```
Full packet: 24 DB 02 00 04 35 01 00 00 BF B7
```

Fixed response to the `0x34` handshake packet.

### 7.3 Log Page Response (0x0B)

```
LEN: 0B (11 decimal)
Payload: 0B [addr_hi] [addr_lo] [event] [b1] [b2] [hour] [min] [day] [month] [year]
```

Returns one 8-byte log page for the requested address. See Section 9 for event codes.

### 7.4 Door Query Response (0x92)

```
LEN: 15 (21 decimal)
Payload: 92 00 [door_number] [flags1] [flags2] [flags3] 
         [serial_FF] 00 00 00 
         [unknown x3] 
         [master_code_hi_bcd] [master_code_lo_bcd] 
         FF FF FF FF FF FF
```

Full captured response (door 1):
```
24 DB 02 00 15 92 00 01 11 01 00 FF 00 00 00 13 89 F0 22 38 FF FF FF FF FF FF 9A 7E
```

Partially decoded (cross-referenced against Hub Manager Info dialog screenshot):

| Byte(s) | Value | Meaning |
|---------|-------|---------|
| [01] | 00 | Door number high byte |
| [02] | 01 | Door number (1) |
| [03] | 0x11 | Status flags — bit 0 = Program Mode active, bit 4 = Door Contact CLOSED |
| [04] | 0x01 | Status flags 2 — bit 0 = REX Input OPEN |
| [05] | 0x00 | Status flags 3 (all OFF) |
| [06] | 0xFF | Serial number (0xFF = 0 / unused) |
| [07-09] | 00 00 00 | Unknown |
| [10-12] | 13 89 F0 | Unknown (possibly part number / firmware encoding) |
| [13-14] | 22 38 | **Master Code in BCD — 0x22 0x38 = "2238"** |
| [15-20] | FF x6 | Unused |

**Known status flags (byte [03]):**
- Bit 0 = Program Mode Entered
- Bit 4 = Door Contact CLOSED (0 = OPEN)

**Known status flags (byte [04]):**
- Bit 0 = REX Input OPEN (0 = CLOSED)

Hub Manager Info dialog also shows: controller type (Max 3 v2), part number (229-0412), firmware rev (01.0B), Passage/Toggle active, Forced Door active, Door Ajar active, Auto Unlock active, Timed Unlock active, Front End Jumper (Wiegand/Keypad), and Door Contact state. Full byte mapping for all these fields was not completed as it is not required for normal app operation.

---

## 8. Complete Session Flows

### 8.1 Add or Delete Users (one-shot)

```
PC  → handshake (04)
CTL → status (05) + device info
PC  → handshake (34)
CTL → ack (35)
PC  → set_datetime (28)
CTL → ack (01)
PC  → add user (90) or delete user (93)  [repeat for each user]
CTL → ack (01)  [for each]
PC  → end session (A0)
```

### 8.2 Read Event Log (one-shot)

```
PC  → handshake (04)
CTL → status (05) + device info
PC  → handshake (34)
CTL → ack (35)
PC  → end session (A0)
CTL → status (11) with log pointers [start_addr, end_addr]
  if start_addr == end_addr: no new events, stop here
PC  → for addr = start_addr; addr < end_addr; addr += 8:
        send read_log_page (0A addr 08)
        receive log_page (0B addr [8 bytes])
PC  → end log (A5)
CTL → ack (01)
PC  → end session (A0)
CTL → updated status (11) with new start_addr = old end_addr
```

---

## 9. Event Log

### Log Page Format (8 bytes)

```
[event_type] [b1] [b2] [hour] [min] [day] [month] [year_2digit]
```

Timestamp fields are plain hexadecimal (not BCD). Hour and min are 24-hour format.

### Event Types

| Code | b1 | b2 | Event Name |
|------|----|----|------------|
| `0x01` | FF | FF | User – Access Denied (Invalid Credential) |
| `0x11` | slot# | FF | User – Access Granted IN |
| `0x17` | 00 | 00 | User – Relock (manual relock via software) |
| `0x32` | 00 | 00 | System – Event Log Retrieved (session marker) |
| `0x34` | 00 | 00 | System – Remote Unlock (manual unlock via software) |

For `0x11` events, `b1` contains the controller slot number of the user who was granted access. Look up the user by slot number in the app database.

All other event codes (door ajar, auto unlock, REX, etc.) are logged by the controller but will be rare or non-existent in normal card-only operation. Display them as "System Event (0xXX)" with the raw code.

---

## 10. Real-World Data

### Site Configuration
- **Site name:** ERC
- **Door name:** Front Door
- **Controller type:** Max 3 v2
- **Controller address:** 2
- **Site code for all cards:** 105

### User Database
- Approximately 530 members
- All use site code 105
- Slot numbers range from low single digits up to ~582, with gaps from deleted users
- No PINs on any real users (card-only access)
- All use timezone index 01 (24 Hour) and access level 01 (ERC Members)

### Card Encoding for Site 105
All real member internal card values begin with `0004D3...`. This is because:
```
site=105 (0x69): (105 << 17) = 0x00D20000
card ranges: ~50500–52035
result prefix: 0004D3...
```

### Slot Number Management
Slot numbers are assigned by Hub Manager and have gaps where users were deleted. The app **must preserve existing slot numbers** exactly — do not reassign. Track which slots are free for new user additions.

### Rolling Counter
The rolling counter in byte [12] of the add user command starts at `0xD0` and increments by 1 with each write to any user. It wraps at `0xFF` back to `0x00`. The app must persist this value across sessions.

---

## 11. Dashboard Polling (Reference Only)

Hub Manager's Dashboard mode uses a continuous polling loop (~32ms cycle). This is **not needed** for a one-shot Rails app but documented for completeness.

### Poll Cycle
```
PC  → A0  (end session / cycle separator)
PC  → 04  (handshake)
CTL → 11  (status with log pointers)
CTL → 05  (device info)
PC  → 29  (request current time)
CTL → 2A [sec_bcd min_bcd hour_bcd dow day_bcd month_bcd year_bcd 00]
PC  → 34  (handshake part 2)
CTL → 35 01 00 00
PC  → 40  (request door state)
CTL → 41 [state_hi state_lo]  (00 00 = normal/locked)
PC  → A0
[repeat]
```

Periodically (every ~5 seconds), the PC also sends:
```
PC → 24 DB 02 00 02 C0 01 [CRC CRC]  (keepalive)
CTL → ACK
```

When the poll cycle detects `log_start != log_end` in the status response, it inserts the log read sequence inline before resuming polling.

### Remote Unlock Command
The exact command to trigger a remote unlock was not fully isolated during capture. Command `0xC0` with varying values is the likely candidate. This should be determined experimentally once the app is running by sending `C0 [01..FF]` values and observing which triggers a `0x34` event in the log.

---

## 12. Known Unknowns

| Item | Status | Impact |
|------|--------|--------|
| Remote unlock exact command | Not confirmed | Can be found experimentally |
| Most system event codes (door ajar, auto unlock, etc.) | Unknown | Cosmetic only — display as raw hex |
| Controller memory capacity / circular buffer wrap behavior | Unknown | Low risk for normal operation |
| Enable/disable user flag in user record | Not captured | Workaround: delete and re-add |

---

## 13. Reference Packets

### Handshake (always identical)
```
PC  → 24 DB 02 00 01 04 1A 1D
CTL → 24 DB 02 00 13 05 02 29 04 12 01 0B 00 00 00 00 00 00 02 04 03 00 00 00 19 B4
PC  → 24 DB 02 00 01 34 2C 4E
CTL → 24 DB 02 00 04 35 01 00 00 BF B7
```

### End Session (always identical)
```
24 DB 02 00 01 A0 EF 73
```

### End Log (always identical)
```
24 DB 02 00 01 A5 BF D6
```

### Set Date/Time Example (2026-02-24 20:50:36 Tuesday)
```
24 DB 02 00 09 28 36 50 20 03 24 02 26 00 E1 DB
```

### Add User Example (slot 0x42, site 105 card 51809, no PIN, tz 01, counter D2)
```
24 DB 02 00 15 90 00 42 21 84 00 01 00 00 00 15 D2 0F FF FF 00 00 04 D3 9A 82 [CRC CRC]
```

### Delete User Example (slot 0x42)
```
24 DB 02 00 03 93 00 42 57 63
```

### Delete Timezone Example (index 02)
```
24 DB 02 00 07 B0 02 FF FF FF FF FF 42 FF
```

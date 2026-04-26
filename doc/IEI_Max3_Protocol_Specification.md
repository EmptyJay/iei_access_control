# IEI Max3 / prox.pad plus — Serial Protocol Specification

**Reverse engineered:** February 24, 2026; updated April 25, 2026  
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
LEN: 15h (21 decimal)
Payload (21 bytes):
[0]  90          command
[1]  slot_hi     upper byte of slot number
[2]  slot_lo     lower byte of slot number
[3]  type_byte   0x21=standard user, 0x11=master PIN (slot 1), 0x01=master card (slot 2)
[4]  access_byte 0x04=standard access level, 0x84=alternate access level, 0x01=master
[5]  00          fixed
[6]  tz_index    time zone: 0x01=24-Hour, 0xFF=all zones (master users only)
[7]  00          fixed
[8]  00          fixed
[9]  00          fixed
[10] counter_hi  high byte of 16-bit rolling write counter
[11] counter_lo  low byte of 16-bit rolling write counter
[12] pin_flag    0x0F=no PIN, 0xF0=has PIN
[13] pin_bcd1    BCD digit pair 1 (e.g. 0x22 = "22"), or 0xFF if no PIN
[14] pin_bcd2    BCD digit pair 2 (e.g. 0x38 = "38" → full PIN "2238"), or 0xFF
[15] padding     0x00 for regular users; 0xFF for master slots 1–2
[16] padding     0x00 for regular users; 0xFF for master slots 1–2
[17] card_b0     card data byte 0 (MSB), or 0xFF if no card
[18] card_b1     card data byte 1, or 0xFF
[19] card_b2     card data byte 2, or 0xFF
[20] card_b3     card data byte 3 (LSB), or 0xFF
```

**Slot number** is 2 bytes big-endian. Slots 1 and 2 are reserved master users (see Section 10). Regular members use slots 3+. The Hub Manager assigns slots equal to the user's DB ID (which started at 1 and has gaps from deleted users). All observed regular slots are ≤ 582.

**Rolling counter** at bytes [10–11] is a 16-bit big-endian value that increments globally with each write to any slot. Hub Manager uses a monotonic counter across the entire session. The app uses a simplified approach: byte[10] fixed at 0x15, byte[11] = 8-bit rolling counter stored in the database (starts at 0xD0, wraps at 0xFF→0x00). This is functionally sufficient — the controller only needs the counter to differ between successive writes to the same slot.

**Access byte [4]:** Hub Manager uses `0x04` for the vast majority of users and `0x84` for a minority (likely those on a different access-level profile). The app uses `0x84` for all users, which is acceptable since access control is managed by deleting/re-adding users rather than by access-level assignment.

**Type byte [3]:** The app always uses `0x21`. Values `0x11` and `0x01` are specific to the pre-programmed master slots and should never be written by the app.

**tz_index:** All regular users use `0x01` (24-Hour, all days). Master slots use `0xFF` (all zones).

#### Card Data Encoding (26-bit HID Prox)

The 26-bit Wiegand format includes facility code, card number, and parity bits packed into a 32-bit word with a fixed format bit at bit 26:

```
bit 26:     1  (HID format indicator, always set)
bit 25:     EP (even parity over bits 24–13)
bits 24–17: facility code (site_code, 8 bits)
bits 16–1:  card number (16 bits)
bit 0:      OP (odd parity over bits 12–1)
```

```python
def encode_card(site_code, card_number):
    raw = (site_code << 17) | (card_number << 1)
    ep_bits = (raw >> 13) & 0xFFF
    ep = 1 if bin(ep_bits).count('1') % 2 else 0
    op_bits = (raw >> 1) & 0xFFF
    op = 1 if bin(op_bits).count('1') % 2 == 0 else 0
    full = (1 << 26) | (ep << 25) | raw | op
    return [(full >> 24) & 0xFF, (full >> 16) & 0xFF,
            (full >> 8) & 0xFF, full & 0xFF]
```

```ruby
def encode_card(site_code, card_number)
  raw = (site_code << 17) | (card_number << 1)
  ep  = ((raw >> 13) & 0xFFF).to_s(2).count("1").odd? ? 1 : 0
  op  = ((raw >>  1) & 0xFFF).to_s(2).count("1").even? ? 1 : 0
  full = (1 << 26) | (ep << 25) | raw | op
  [(full >> 24) & 0xFF, (full >> 16) & 0xFF, (full >> 8) & 0xFF, full & 0xFF]
end
```

**Examples (site code 105):**
| Site | Card | Encoded bytes |
|------|------|---------------|
| 105 | 51770 | `04 D3 94 75` |
| 1 | 1 | `06 02 00 02` |
| 1 | 2 | `06 02 00 04` |

All real ERC members use site code **105**. Their card bytes always begin with `04 D3...`.

---

### 6.3 Delete User (0x93)

```
LEN: 03
Payload: 93 [slot_hi] [slot_lo]
```

The slot is always 2 bytes big-endian regardless of value. Hub Manager walks a range of slot numbers during a full export (observed: slots 73–2000) to clear all possible occupied slots before re-adding users.

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

Times are plain hex (24-hour). `0x00:0x00` = midnight, `0x23:0x59` = 23:59.

**Examples:**
- 24 Hour (all days, midnight to 23:59): `B0 01 FF 00 00 23 59`
- Clear timezone slot (unused): `B0 [index] FF FF FF FF FF`

During a full export Hub Manager writes timezone index 01 as 24-Hour and clears indices 02–08. For the app, only timezone index `0x01` (24 Hour) is used and does not need to be reprogrammed.

---

### 6.5 Write Access Level (0xB3)

```
LEN: 05
Payload: B3 [index] [b1] [b2] [b3] [b4]
```

Programs one of 32 access level slots. Hub Manager writes all 32 entries (indices 0x01–0x20) with `FF FF FF FF` during a full export (clearing all access level definitions). The payload bytes after the index are not fully decoded; `FF FF FF FF` appears to mean "no restriction / cleared."

The app does not use this command. Access control is managed at the user level by deleting and re-adding users.

---

### 6.6 Write Holiday (0x37)

```
LEN: 08
Payload: 37 01 00 [entry_hi] [entry_lo] [month] [day] [year] [flags]
```

Programs one holiday schedule entry. Hub Manager writes 500 entries (all zeroed = no holidays defined) during a full export. Bytes [1–2] appear fixed as `01 00`; bytes [3–4] are the entry number (1-indexed); remaining bytes define the holiday date/flags (all `00` when clearing).

The app does not use this command.

---

### 6.7 Controller Configuration (0x25)

Five variable-length sub-packets sent during a full export. Sub-command is the second byte (payload[1]).

| Sub-cmd | Full packet |
|---------|-------------|
| 0x00 | `24 DB 02 00 0A 25 00 03 05 00 0A 0B FF 04 00 B1 4E` |
| 0x1C | `24 DB 02 00 06 25 1C 01 03 03 04 BC 7B` |
| 0x6E | `24 DB 02 00 04 25 6E 00 00 13 4A` |
| 0x70 | `24 DB 02 00 0D 25 70 F7 00 FE 6F 0C 00 5C 00 23 3F 00 80 74` |
| 0xF0 | `24 DB 02 00 12 25 F0 00 05 00 05 00 05 00 05 00 05 00 05 00 05 00 05 25 F7` |

Sub-cmd 0xF0 appears to configure door strike timing (repeated pattern of `05 00` × 8, one per door). Sub-cmds 0x00 and 0x70 contain unknown controller parameters. The app does not use any 0x25 sub-commands.

---

### 6.8 Unknown Pre-Master-User Command (0x3A)

```
LEN: 02
Payload: 3A F8 01
Full packet: 24 DB 02 00 03 3A F8 01 96 A1
```

Sent exactly once during a full export, immediately before writing slot 1 (the master PIN user). Purpose unknown. The app does not use this command.

---

### 6.9 End Session (0xA0)

```
LEN: 01
Payload: A0
Full packet: 24 DB 02 00 01 A0 EF 73
```

Sent to close a session. Also used as a keep-alive prefix in the dashboard polling loop.

---

### 6.10 End Log Read (0xA5)

```
LEN: 01
Payload: A5
Full packet: 24 DB 02 00 01 A5 BF D6
```

Sent after reading all log pages to signal end of log import.

---

### 6.11 Read Log Page (0x0A)

```
LEN: 04
Payload: 0A [addr_hi] [addr_lo] 08
```

Reads one 8-byte log page from controller memory. The address increments by 8 for each successive page. The range to read comes from the status response log pointers.

---

### 6.12 Door Query (0x91)

```
LEN: 03
Payload: 91 00 [door_number]
Full packet (door 1): 24 DB 02 00 03 91 00 01 41 A4
```

Requests status and hardware info for the specified door. Not required for normal operation but useful for a health check / status page in the app.

Controller responds with cmd `0x92` (see Section 7.4).

---

## 7. Controller Responses

### 7.1 ACK (0x01)

```
LEN: 03
Payload: 01 [crc_hi] [crc_lo]
```

The two bytes echoed are the CRC of the command being acknowledged. Used to confirm receipt of: set_datetime, add user, delete user, write/delete timezone, write access level, write holiday, write config, and the 0x3A command.

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
Full captured response (door 1):
24 DB 02 00 15 92 00 01 11 01 00 FF 00 00 00 13 89 F0 22 38 FF FF FF FF FF FF 9A 7E
```

Partially decoded:

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

**Note:** bytes [10–12] match the counter value of slot 1 (0x1389) plus the pin_flag (0xF0). This region may encode the master user's write counter and PIN flag rather than part number/firmware.

**Known status flags (byte [03]):**
- Bit 0 = Program Mode Entered
- Bit 4 = Door Contact CLOSED (0 = OPEN)

**Known status flags (byte [04]):**
- Bit 0 = REX Input OPEN (0 = CLOSED)

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

### 8.3 Full Export / Factory Reset (Hub Manager reference flow)

Observed in capture on 2026-04-25. This is what Hub Manager Pro does when performing a full export to controller. The app does not replicate this flow, but it is documented for completeness.

```
PC  → handshake (04)
CTL → status (05)
PC  → handshake (34)
CTL → ack (35)
PC  → set_datetime (28)
CTL → ack (01)
PC  → write timezone (B0) × 8   [index 01 = 24-Hour; indices 02-08 cleared]
CTL → ack (01) × 8
PC  → controller config (25) × 5  [sub-cmds 00, 1C, 6E, 70, F0]
CTL → ack (01) × 5
PC  → unknown command (3A F8 01)
CTL → ack (01)
PC  → add user (90) slot 1  [master PIN user: type=0x11, PIN=2238]
CTL → ack (01)
PC  → add user (90) slot 2  [master card user: type=0x01, no PIN, no card]
CTL → ack (01)
PC  → add user (90) × N    [regular users, slots 3+]
CTL → ack (01) × N
PC  → write access level (B3) × 32  [all 32 entries cleared with FF FF FF FF]
CTL → ack (01) × 32
PC  → write holiday (37) × 500  [all 500 holiday slots cleared]
CTL → ack (01) × 500
PC  → end session (A0)
```

**Note:** In the captured export, the delete-then-add pattern was not used. The 1791 delete packets (0x93) appear in a separate earlier session that walked slots 73–2000. The full export session itself only adds users. The app's sync approach (add active users, delete inactive ones) is a simplified but functionally equivalent flow.

---

## 9. Event Log

### Log Page Format (8 bytes)

```
[event_type] [b1] [b2] [hour_bcd] [min_bcd] [month_bcd] [day_bcd] [year_bcd]
```

Timestamp fields are **BCD encoded** (not plain hex). Hour is 24-hour format.
Field order is month then day (not day then month as originally documented).

### Event Types

| Code | b1 | b2 | Event Name |
|------|----|----|------------|
| `0x01` | FF | FF | User – Access Denied (Invalid Credential) |
| `0x11` | slot# | FF | User – Access Granted IN |
| `0x17` | 00 | 00 | User – Relock (manual relock via software) |
| `0x32` | 00 | 00 | System – Event Log Retrieved (session marker) |
| `0x34` | 00 | 00 | System – Remote Unlock (manual unlock via software) |

For `0x11` events, `b1` and `b2` together form a 16-bit big-endian slot number: `slot = (b1 << 8) | b2`. Look up the user by slot in the app database.

All other event codes (door ajar, auto unlock, REX, etc.) are logged by the controller but rare in normal card-only operation. Display them as "System Event (0xXX)" with the raw code.

---

## 10. Reserved Master Slots (Slots 1 and 2)

Slots 1 and 2 are pre-programmed master users that the app never touches.

**Slot 1 — Master PIN User:**
```
Full packet: 24 DB 02 00 15 90 00 01 11 01 00 FF 00 00 00 13 89 F0 22 38 FF FF FF FF FF FF 21 B3
Payload:     90 00 01 11 01 00 FF 00 00 00 13 89 F0 22 38 FF FF FF FF FF FF
```
- type_byte=0x11, access_byte=0x01, tz_index=0xFF (all zones)
- pin_flag=0xF0 (has PIN), PIN = BCD "22" "38" = **2238**
- No card (card bytes = FF FF FF FF FF FF)

**Slot 2 — Secondary Master (no PIN, no card):**
```
Full packet: 24 DB 02 00 15 90 00 02 01 01 00 FF 00 00 00 13 8A 0F FF FF FF FF FF FF FF FF 93 6E
Payload:     90 00 02 01 01 00 FF 00 00 00 13 8A 0F FF FF FF FF FF FF FF FF
```
- type_byte=0x01, access_byte=0x01, tz_index=0xFF
- pin_flag=0x0F (no PIN), no card

The master PIN code (2238) is stored in the controller and used for keypad programming mode. It is transmitted as part of the add_user packet for slot 1 during a full export. It is **not** transmitted during the session handshake — the handshake is fixed bytes with no password field.

---

## 11. Real-World Data

### Site Configuration
- **Site name:** ERC
- **Door name:** Front Door
- **Controller type:** Max 3 v2
- **Controller address:** 2
- **Site code for all cards:** 105

### User Database
- Approximately 530 members
- All use site code 105
- Slot numbers range from 3 up to ~582, with gaps from deleted users
- Slots 1 and 2 are reserved master users (never managed by app)
- No PINs on any regular users (card-only access)
- All use timezone index 01 (24 Hour)

### Card Encoding for Site 105
All real member internal card values begin with `04 D3...`. This is because:
```
site=105 (0x69): encoded as HID 26-bit Wiegand with parity
result prefix: 04 D3...
```

### Slot Number Management
Slot numbers are assigned by Hub Manager and have gaps where users were deleted. The app **must preserve existing slot numbers** exactly — do not reassign. Track which slots are free for new user additions.

### Rolling Counter
The counter at payload bytes [10–11] is 16-bit big-endian in the actual protocol. Hub Manager uses a monotonic counter that increments with every write across all users. The app uses a simplified approach: byte[10] = fixed 0x15, byte[11] = 8-bit counter stored in the `settings` table (starts at 0xD0, wraps at 0xFF→0x00). This deviates from the full protocol but is functionally sufficient.

### Tier System (App-Level Concept)
The app assigns each user a `tier` of either `standard` or `officer`. This concept does not exist at the controller level — the controller treats all users identically. Tier is enforced purely by the app: during lockdown, standard-tier users are deleted from the controller; officer-tier users remain. Access is restored by re-adding standard users.

---

## 12. Dashboard Polling (Reference Only)

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

## 13. Known Unknowns

| Item | Status | Impact |
|------|--------|--------|
| Remote unlock exact command | Not confirmed | Can be found experimentally |
| Most system event codes (door ajar, auto unlock, etc.) | Unknown | Cosmetic only — display as raw hex |
| Controller memory capacity / circular buffer wrap behavior | Unknown | Low risk for normal operation |
| Exact meaning of 0x3A F8 01 command | Unknown | App does not use it; safe to omit |
| Exact semantics of 0xB3 payload bytes (access level definition) | Unknown | App does not use 0xB3 |
| Byte [4] in 0x92 door query response at offsets [10-12] | Unclear | May overlap counter/pin_flag of slot 1 |

---

## 14. Reference Packets

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

### Add User Example — slot 3, site 105, standard user (from full export)
```
24 DB 02 00 15 90 00 03 21 04 00 01 00 00 00 14 90 0F FF FF 00 00 04 D3 8E 11 C5 E8
```
Decoded: slot=3, type=0x21(standard), access=0x04, tz=01, counter=0x1490, no PIN, card=04 D3 8E 11

### Add User Example — slot 1, master PIN user (from full export)
```
24 DB 02 00 15 90 00 01 11 01 00 FF 00 00 00 13 89 F0 22 38 FF FF FF FF FF FF 21 B3
```
Decoded: slot=1, type=0x11(master PIN), access=0x01, tz=0xFF(all), counter=0x1389, PIN=2238, no card

### Add User Example — app-generated (slot 0x42, site 105, card 51809, counter D2 using app approach)
```
24 DB 02 00 15 90 00 42 21 84 00 01 00 00 00 15 D2 0F FF FF 00 00 04 D3 9A 82 [CRC CRC]
```
Note: this uses byte[4]=0x84 and byte[10]=0x15 (fixed) — the app's simplified approach.

### Delete User Example (slot 0x0042)
```
24 DB 02 00 03 93 00 42 57 63
```

### Delete User Example (slot 0x07D0 = 2000)
```
24 DB 02 00 03 93 07 D0 6D 0F
```

### Write Timezone Example (index 01, 24-Hour)
```
24 DB 02 00 07 B0 01 FF 00 00 23 59 8D B9
```

### Clear Timezone Example (index 02)
```
24 DB 02 00 07 B0 02 FF FF FF FF FF 42 FF
```

### Write Access Level Example (index 01, cleared)
```
24 DB 02 00 06 B3 01 FF FF FF FF 79 E2
```

### Write Holiday Example (entry 1, cleared)
```
24 DB 02 00 09 37 01 00 01 00 00 00 00 00 E0 C7
```

### Unknown Command 0x3A
```
24 DB 02 00 03 3A F8 01 96 A1
```

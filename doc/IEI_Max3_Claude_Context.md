# IEI Max3 Protocol — Claude Session Context

This file provides complete context for continuing development of a Rails-based access control system that communicates with an IEI Max3 v2 door controller over RS-485 serial. All protocol details were reverse engineered from packet captures of Hub Manager Pro v8.

---

## Project Goal

Replace Hub Manager Pro v8 (Windows software) with a custom Ruby on Rails web application running on a Raspberry Pi 4. The Pi connects to the IEI Max3 controller via USB-to-RS485 adapter. The app manages ~530 members with card-only (no PIN) access to a single door.

**Stack:**
- Ruby on Rails (web UI + API)
- SQLite (database)
- Puma (web server)
- rubyserial gem (RS-485 communication)
- Raspberry Pi 4 (2GB), Raspberry Pi OS Lite

---

## Serial Configuration

- RS-485, 19200 baud, 8N1
- Controller address: 2
- Site name: ERC, Door: Front Door

---

## Packet Structure

```
[24 DB 02 00] [LEN] [PAYLOAD...] [CRC_HI CRC_LO]
```

CRC is CRC-CCITT, polynomial 0x1021, **init value 0x7B6D** (non-standard).  
CRC is calculated over: [LEN byte] + [all PAYLOAD bytes].

```ruby
def crc16_ccitt(data)
  crc = 0x7B6D
  data.each do |byte|
    crc ^= (byte << 8)
    8.times { crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1) }
    crc &= 0xFFFF
  end
  crc
end

def build_packet(payload_bytes)
  len = payload_bytes.length
  crc = crc16_ccitt([len] + payload_bytes)
  [0x24, 0xDB, 0x02, 0x00, len] + payload_bytes + [crc >> 8, crc & 0xFF]
end
```

---

## Handshake (required at start of every session)

```
PC  → 24 DB 02 00 01 04 1A 1D
CTL → 24 DB 02 00 13 05 [18 bytes] [CRC CRC]   ← status/device info
PC  → 24 DB 02 00 01 34 2C 4E
CTL → 24 DB 02 00 04 35 01 00 00 BF B7
```

These 4 packets are always identical. Hard-code them.

---

## Fixed Packets (always identical, hard-code these)

```ruby
HANDSHAKE_1   = [0x24,0xDB,0x02,0x00,0x01,0x04,0x1A,0x1D]
HANDSHAKE_2   = [0x24,0xDB,0x02,0x00,0x01,0x34,0x2C,0x4E]
END_SESSION   = [0x24,0xDB,0x02,0x00,0x01,0xA0,0xEF,0x73]
END_LOG       = [0x24,0xDB,0x02,0x00,0x01,0xA5,0xBF,0xD6]
```

---

## Commands

### Set Date/Time
```ruby
def set_datetime_packet(time = Time.now)
  payload = [0x28, time.sec, time.min, time.hour,
             time.wday, time.day, time.month, time.year % 100, 0x00]
  build_packet(payload)
end
```
All time fields are plain hex. `time.wday` is 0=Sun..6=Sat — matches controller.

### Add / Update User
```ruby
# slot: integer (1..582+, preserving existing assignments)
# card_bytes: 4-byte array from encode_card()
# tz_index: 0x01 for all real members (24-Hour / ERC Members)
# counter: rolling byte, starts 0xD0, increments each write, wraps at 0xFF→0x00

def add_user_packet(slot, card_bytes, tz_index: 0x01, counter:)
  slot_hi = (slot >> 8) & 0xFF
  slot_lo = slot & 0xFF
  payload = [0x90, 0x00, slot_hi, slot_lo,
             0x21, 0x84, 0x00, tz_index, 0x00, 0x00, 0x00,
             0x15, counter,
             0x0F, 0xFF, 0xFF,   # no PIN
             0x00, 0x00] + card_bytes
  build_packet(payload)
end
```

### Delete User
```ruby
def delete_user_packet(slot)
  slot_hi = (slot >> 8) & 0xFF
  slot_lo = slot & 0xFF
  build_packet([0x93, slot_hi, slot_lo])
end
```

### Card Data Encoding (26-bit HID Prox, site code 105 for all real members)
```ruby
def encode_card(site_code, card_number)
  raw = (site_code << 17) | (card_number << 1)
  [(raw >> 24) & 0xFF, (raw >> 16) & 0xFF, (raw >> 8) & 0xFF, raw & 0xFF]
end
# Example: site=105, card=51770 → [0x04, 0xD3, 0x94, 0x75]
```

### Read Log Page
```ruby
def read_log_page_packet(addr)
  addr_hi = (addr >> 8) & 0xFF
  addr_lo = addr & 0xFF
  build_packet([0x0A, addr_hi, addr_lo, 0x08])
end
```

### Door Query (optional — for status/health page)
```ruby
DOOR_QUERY = build_packet([0x91, 0x00, 0x01])
# Full packet: 24 DB 02 00 03 91 00 01 41 A4

def parse_door_query_response(packet)
  payload = packet[5..-3]
  return nil unless payload[0] == 0x92
  {
    door:         payload[2],
    program_mode: (payload[3] & 0x01) != 0,
    door_contact: (payload[3] & 0x10) != 0 ? :closed : :open,
    rex_input:    (payload[4] & 0x01) != 0 ? :open : :closed,
    master_code:  (payload[13].to_s(16).rjust(2,'0') + payload[14].to_s(16).rjust(2,'0')).to_i.to_s
    # master_code: BCD e.g. 0x22 0x38 = "2238"
  }
end
# Send after handshake, no ACK — response is the 0x92 packet directly
```

---

## Status Response (cmd 0x11) — Parsing Log Pointers

The controller sends this after `END_SESSION` when log data is available, and also after a log read session.

```ruby
def parse_status_response(packet)
  # packet is the full raw byte array including header and CRC
  # payload starts at index 5
  payload = packet[5..-3]  # strip header(5) and CRC(2)
  return nil unless payload[0] == 0x11

  {
    log_start: (payload[8] << 8) | payload[9],
    log_end:   (payload[10] << 8) | payload[11],
    hour:      payload[12],
    min:       payload[13],
    day:       payload[14],
    month:     payload[15],
    year:      2000 + payload[16]
  }
end
# If log_start == log_end: no new events
```

---

## Session Flow: Sync Users

```ruby
# Add or delete users
send(HANDSHAKE_1)
recv  # status/device info (0x05)
send(HANDSHAKE_2)
recv  # handshake ack (0x35)
send(set_datetime_packet)
recv  # ACK (0x01)
users_to_add.each do |user|
  send(add_user_packet(user.slot, encode_card(105, user.card_number), counter: next_counter))
  recv  # ACK (0x01)
end
users_to_delete.each do |slot|
  send(delete_user_packet(slot))
  recv  # ACK (0x01)
end
send(END_SESSION)
```

---

## Session Flow: Read Event Log

```ruby
send(HANDSHAKE_1)
recv  # status (0x05)
send(HANDSHAKE_2)
recv  # ack (0x35)
send(END_SESSION)

status_packet = recv  # status (0x11) with log pointers
status = parse_status_response(status_packet)

if status[:log_start] == status[:log_end]
  # No new events
else
  addr = status[:log_start]
  while addr < status[:log_end]
    send(read_log_page_packet(addr))
    page = recv  # log page response (0x0B)
    process_log_page(page)
    addr += 8
  end
  send(END_LOG)
  recv  # ACK
  send(END_SESSION)
  recv  # updated status with new log_start
end
```

---

## Log Page Parsing

```ruby
def process_log_page(packet)
  # payload starts at index 5
  payload = packet[5..-3]
  return unless payload[0] == 0x0B

  addr      = (payload[1] << 8) | payload[2]
  event     = payload[3]
  b1        = payload[4]
  b2        = payload[5]
  hour      = payload[6]
  min       = payload[7]
  day       = payload[8]
  month     = payload[9]
  year      = 2000 + payload[10]

  timestamp = Time.new(year, month, day, hour, min, 0)

  case event
  when 0x01  # Access Denied
    AccessEvent.create!(event_type: 'denied', occurred_at: timestamp)
  when 0x11  # Access Granted
    user = User.find_by(slot: b1)
    AccessEvent.create!(event_type: 'granted', user: user, occurred_at: timestamp)
  when 0x17  # Relock
    AccessEvent.create!(event_type: 'relock', occurred_at: timestamp)
  when 0x32  # Log session marker (ignore or record)
    # skip
  when 0x34  # Remote Unlock
    AccessEvent.create!(event_type: 'remote_unlock', occurred_at: timestamp)
  else
    AccessEvent.create!(event_type: "unknown_0x#{event.to_s(16).upcase.rjust(2,'0')}", occurred_at: timestamp)
  end
end
```

---

## Event Code Reference

| Hex | b1 | b2 | Description |
|-----|----|----|-------------|
| 0x01 | FF | FF | Access Denied – Invalid Credential |
| 0x11 | slot# | FF | Access Granted IN |
| 0x17 | 00 | 00 | User – Relock |
| 0x32 | 00 | 00 | System – Event Log Retrieved (session marker) |
| 0x34 | 00 | 00 | System – Remote Unlock |

For 0x11, `b1` is the controller slot number. Use `User.find_by(slot: b1)` to get the user name.

---

## ACK Verification

The controller ACKs commands by echoing the CRC of the command:
```ruby
def valid_ack?(ack_packet, sent_packet)
  # ACK payload: [0x01, sent_crc_hi, sent_crc_lo]
  ack_payload = ack_packet[5..-3]
  return false unless ack_payload[0] == 0x01
  sent_crc_hi = sent_packet[-2]
  sent_crc_lo = sent_packet[-1]
  ack_payload[1] == sent_crc_hi && ack_payload[2] == sent_crc_lo
end
```

---

## Database Schema (suggested)

```ruby
# Users table
create_table :users do |t|
  t.string  :name,        null: false
  t.integer :slot,        null: false   # controller slot number, preserve existing
  t.integer :site_code,   default: 105
  t.integer :card_number, null: false
  t.boolean :active,      default: true
  t.boolean :synced,      default: false  # false = pending sync to controller
  t.timestamps
end
add_index :users, :slot, unique: true
add_index :users, :card_number

# Access events table
create_table :access_events do |t|
  t.references :user, foreign_key: true, null: true  # null for denied events
  t.string  :event_type,  null: false  # 'granted','denied','remote_unlock','relock','unknown_0xXX'
  t.datetime :occurred_at, null: false
  t.timestamps
end
add_index :access_events, :occurred_at

# App settings table (for rolling counter etc.)
create_table :settings do |t|
  t.string  :key,   null: false, index: { unique: true }
  t.string  :value, null: false
end
# Seed: Setting.create!(key: 'rolling_counter', value: 'D0')
```

---

## Key Implementation Notes

1. **Rolling counter** — persist in `settings` table as hex string. Load before any sync, increment after each user write, save after sync completes. Wraps `0xFF → 0x00`.

2. **Slot management** — never reassign existing slots. When adding a new user, find the lowest slot number not in use. Seed the database with all existing members and their current slot numbers from the Hub Manager export.

3. **Sync strategy** — track `synced: false` on users added/modified/deleted. On sync, only send commands for changed records (Hub Manager calls this "Export Changes Only").

4. **Card encoding** — all real members use site code 105. New members added via the app also use site code 105.

5. **Timezone/access level** — always use index `0x01` for all users. No timezone management needed in the app.

6. **Serial timing** — wait for ACK/response before sending next command. The controller is half-duplex RS-485. A timeout of ~500ms per command is safe.

7. **Remote unlock** — the exact `0xC0` command value for triggering unlock was not fully isolated during capture. Determine experimentally: send `C0 01`, `C0 02`, etc. and observe which produces a `0x34` event in the log. Hub Manager sends `C0 01` periodically as a keepalive; the actual unlock may use a different byte.

---

## Seeding from Hub Manager Export

The Hub Manager database export (plain text) contains all ~530 existing members with their slot numbers, card numbers, and names. Parse it at setup time to seed the Rails database.

Export format (tab-separated columns):
```
[slot]  [name]  [group]  [card_num]  [internal_value]  [card_num_dup]  [site_code]  [tz]  [0]  [0]  [flag1]  [flag2]
```

Example line:
```
476  Shiffer, Joe  ERC Members  51770  0004D39475  51770  105  0  0  0  No  Yes
```

Internal value format is `0004D3XXYY` for site 105 — use `card_number` column directly and encode via `encode_card(105, card_number)`.

---

## Files in This Project

- `IEI_Max3_Protocol_Specification.md` — Full human-readable protocol spec with examples
- `IEI_Max3_Claude_Context.md` — This file (optimized for Claude session import)
- Captures 01–26: HHD Device Monitoring Studio hex dumps (raw evidence)
- Capture 18: Hub Manager database export (plain text, all members)
- Captures 21, 23, 24: Hub Manager CSV event logs
- Capture 26: Door query / Info dialog (0x91 command, 0x92 response)

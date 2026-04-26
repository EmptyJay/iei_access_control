# Max3Protocol — pure packet building and parsing for the IEI Max3 v2 door controller.
#
# Protocol: RS-485, 19200 baud 8N1, controller address 2.
# Packet structure: [24 DB 02 00] [LEN] [PAYLOAD...] [CRC_HI CRC_LO]
# CRC: CRC-CCITT, poly 0x1021, non-standard init 0x7B6D, calculated over [LEN] + [PAYLOAD].
#
# This module contains no I/O. Include it in Max3Session or use it standalone.
module Max3Protocol
  # ── Fixed packets (always identical) ────────────────────────────────────────

  HEADER      = [0x24, 0xDB, 0x02, 0x00].freeze
  HANDSHAKE_1 = [0x24, 0xDB, 0x02, 0x00, 0x01, 0x04, 0x1A, 0x1D].freeze
  HANDSHAKE_2 = [0x24, 0xDB, 0x02, 0x00, 0x01, 0x34, 0x2C, 0x4E].freeze
  END_SESSION  = [0x24, 0xDB, 0x02, 0x00, 0x01, 0xA0, 0xEF, 0x73].freeze
  END_LOG      = [0x24, 0xDB, 0x02, 0x00, 0x01, 0xA5, 0xBF, 0xD6].freeze

  # ── CRC ─────────────────────────────────────────────────────────────────────

  # CRC-CCITT, polynomial 0x1021, non-standard init 0x7B6D.
  # Calculated over [LEN byte] + [all PAYLOAD bytes].
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
    HEADER + [len] + payload_bytes + [crc >> 8, crc & 0xFF]
  end

  # ── Commands ─────────────────────────────────────────────────────────────────

  # Set Date/Time (cmd 0x28).
  # All time fields are BCD-encoded (confirmed from Hub Manager captures).
  # wday: 1=Sun..7=Sat (Hub Manager format; Ruby Time#wday is 0=Sun..6=Sat).
  def set_datetime_packet(time = Time.now)
    payload = [0x28, bcd_encode(time.sec), bcd_encode(time.min), bcd_encode(time.hour),
               time.wday + 1,
               bcd_encode(time.day), bcd_encode(time.month), bcd_encode(time.year % 100), 0x00]
    build_packet(payload)
  end

  # Add / Update User (cmd 0x90).
  #
  # slot        — controller slot number (1..582+)
  # card_bytes  — 4-byte array from encode_card()
  # tz_index    — 0x01 for all ERC members (24-Hour / all-day access)
  # counter     — rolling byte (integer 0..255); use Setting.increment_counter!
  #
  # NOTE: the context doc had an extra fixed 0x00 at byte [1] — that was wrong.
  # The correct format confirmed by reference packet: 90 [slot_hi] [slot_lo] ...
  def add_user_packet(slot, card_bytes, tz_index: 0x01, counter:)
    slot_hi = (slot >> 8) & 0xFF
    slot_lo = slot & 0xFF
    payload = [0x90, slot_hi, slot_lo,
               0x21, 0x84, 0x00, tz_index, 0x00, 0x00, 0x00,
               0x15, counter,
               0x0F, 0xFF, 0xFF,   # no PIN
               0x00, 0x00] + card_bytes
    build_packet(payload)
  end

  # Delete User (cmd 0x93).
  def delete_user_packet(slot)
    slot_hi = (slot >> 8) & 0xFF
    slot_lo = slot & 0xFF
    build_packet([0x93, slot_hi, slot_lo])
  end

  # Read Log Page (cmd 0x0A). Address increments by 8 per page.
  def read_log_page_packet(addr)
    addr_hi = (addr >> 8) & 0xFF
    addr_lo = addr & 0xFF
    build_packet([0x0A, addr_hi, addr_lo, 0x08])
  end

  # Door Query (cmd 0x91). Returns door status (contact, REX, program mode).
  def door_query_packet(door_number = 1)
    build_packet([0x91, 0x00, door_number])
  end

  # ── Card Data Encoding ───────────────────────────────────────────────────────

  # 26-bit HID Prox encoding. All ERC members use site_code 105.
  #
  # The spec's original formula was missing the Wiegand parity bits. The full
  # 32-bit card word is:
  #   bit 26:    1  (HID format/start bit, always 1)
  #   bit 25:    EP (even parity over bits 24–13)
  #   bits 24–17: facility code (site_code)
  #   bits 16–1:  card number
  #   bit 0:     OP (odd parity over bits 12–1)
  #
  # Verified against all spec reference examples:
  #   encode_card(105, 51770) => [0x04, 0xD3, 0x94, 0x75]
  #   encode_card(  1,     1) => [0x06, 0x02, 0x00, 0x02]
  #   encode_card(  1,     2) => [0x06, 0x02, 0x00, 0x04]
  def encode_card(site_code, card_number)
    raw = (site_code << 17) | (card_number << 1)

    ep_bits = (raw >> 13) & 0xFFF
    ep = ep_bits.to_s(2).count("1").odd? ? 1 : 0

    op_bits = (raw >> 1) & 0xFFF
    op = op_bits.to_s(2).count("1").even? ? 1 : 0

    full = (1 << 26) | (ep << 25) | raw | op
    [(full >> 24) & 0xFF, (full >> 16) & 0xFF, (full >> 8) & 0xFF, full & 0xFF]
  end

  # ── Response Parsing ─────────────────────────────────────────────────────────

  # Parse the status response that follows END_SESSION when log data is available.
  # The packet has LEN=0x11 (17 bytes); the first payload byte is 0xA1.
  # Payload layout: [A1 92 80 D1 08 08 00] [log_start_hi log_start_lo] [log_end_hi log_end_lo]
  #                 [hour] [min] [day] [month] [year_2digit] [00 00]
  # Returns a hash with log pointers, or nil if not a recognised status packet.
  def parse_status_response(packet)
    payload = packet[5..-3]
    return nil unless payload&.first == 0xA1

    {
      log_start: (payload[7] << 8) | payload[8],
      log_end:   (payload[9] << 8) | payload[10],
      hour:      payload[11],
      min:       payload[12],
      day:       payload[13],
      month:     payload[14],
      year:      2000 + payload[15]
    }
  end

  # Verify that an ACK packet correctly acknowledges a sent packet.
  # The controller ACKs by echoing [0x01, crc_hi, crc_lo] of the sent packet.
  def valid_ack?(ack_packet, sent_packet)
    ack_payload = ack_packet[5..-3]
    return false unless ack_payload&.first == 0x01
    ack_payload[1] == sent_packet[-2] && ack_payload[2] == sent_packet[-1]
  end

  # Parse one log page response (cmd 0x0B) and create an AccessEvent record.
  # Returns the created AccessEvent, or nil for session-marker events (0x32).
  #
  # Timestamp fields are BCD-encoded. Field order (verified against live data):
  #   payload[6]=hour, [7]=min, [8]=month, [9]=day, [10]=year_2digit
  def process_log_page(packet)
    payload = packet[5..-3]
    return unless payload&.first == 0x0B

    event          = payload[3]
    write_counter  = (payload[4] << 8) | payload[5]  # (counter_hi << 8) | counter_lo from add_user
    hour    = bcd(payload[6])
    min     = bcd(payload[7])
    month   = bcd(payload[8])
    day     = bcd(payload[9])
    year    = 2000 + bcd(payload[10])

    timestamp = Time.new(year, month, day, hour, min, 0)

    case event
    when 0x01  # Access Denied – Invalid Credential
      AccessEvent.create!(event_type: "denied", occurred_at: timestamp)
    when 0x11  # Access Granted IN — write_counter is (counter_hi << 8) | counter_lo from add_user packet
      user = User.find_by(write_counter: write_counter)
      AccessEvent.create!(event_type: "granted", user: user, occurred_at: timestamp)
    when 0x32  # System – Event Log Retrieved (session marker, skip)
      nil
    else
      event_label = "unknown_0x#{event.to_s(16).upcase.rjust(2, '0')}"
      AccessEvent.create!(event_type: event_label, occurred_at: timestamp)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Format a byte array as a hex string for logging/debugging.
  def hex_str(bytes)
    bytes.map { |b| format("%02X", b) }.join(" ")
  end

  # Decode a BCD-encoded byte to an integer. e.g. 0x19 → 19, 0x44 → 44.
  def bcd(byte)
    (byte >> 4) * 10 + (byte & 0x0F)
  end

  # Encode an integer as a BCD byte. e.g. 19 → 0x19, 44 → 0x44.
  def bcd_encode(n)
    ((n / 10) << 4) | (n % 10)
  end
end

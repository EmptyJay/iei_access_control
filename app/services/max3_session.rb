# Max3Session — manages a single RS-485 serial session with the IEI Max3 v2 controller.
#
# Usage:
#   Max3Session.open do |s|
#     s.sync_users
#   end
#
# Environment variable MAX3_PORT overrides the default serial port.
# Development default: /dev/ttyUSB0 (change to your Mac's /dev/tty.usbserial-* for local testing)
class Max3Session
  include Max3Protocol

  DEFAULT_PORT = ENV.fetch("MAX3_PORT", "/dev/ttyUSB0")
  BAUD_RATE    = 19200
  READ_TIMEOUT = 1      # seconds; controller responds within ~50ms under normal conditions

  # Opens a session, yields it to the block, then closes the port.
  def self.open(port = DEFAULT_PORT)
    session = new(port)
    yield session
  ensure
    session&.close
  end

  def initialize(port = DEFAULT_PORT)
    @port   = port
    @serial = Serial.new(port, BAUD_RATE, 8, :none, 1)
    Rails.logger.info "[Max3] Opened #{port} at #{BAUD_RATE} baud"
  end

  def close
    @serial.close
    Rails.logger.info "[Max3] Port closed"
  end

  # ── Session Flows ────────────────────────────────────────────────────────────

  # Sync all pending users (added, modified, or deleted) to the controller.
  # Marks users as synced: true on success.
  def sync_users
    handshake!
    send_and_ack(set_datetime_packet)

    to_add    = User.pending_sync.active.to_a
    to_delete = User.pending_sync.inactive.to_a

    to_add.each do |user|
      counter  = Setting.increment_counter!
      card     = encode_card(user.site_code, user.card_number)
      packet   = add_user_packet(user.slot, card, counter: counter)
      send_and_ack(packet)
      user.update!(synced: true, write_counter: (0x15 << 8) | counter)
      Rails.logger.info "[Max3] Added slot #{user.slot} (#{user.full_name})"
    end

    to_delete.each do |user|
      send_and_ack(delete_user_packet(user.slot))
      user.destroy!
      Rails.logger.info "[Max3] Deleted slot #{user.slot}"
    end

    send_raw(END_SESSION)
    Rails.logger.info "[Max3] Sync complete — #{to_add.count} added, #{to_delete.count} deleted"
  end

  # Read log pages without advancing the pointer or writing to the database.
  # Prints each page as hex. Safe to run repeatedly — no side effects.
  def peek_event_log
    handshake!
    send_raw(END_SESSION)

    status_packet = recv_packet
    status = parse_status_response(status_packet)

    unless status
      Rails.logger.warn "[Max3] Unexpected response after END_SESSION: #{hex_str(status_packet)}"
      return
    end

    Rails.logger.info "[Max3] Log start: 0x#{status[:log_start].to_s(16).upcase}, end: 0x#{status[:log_end].to_s(16).upcase}"

    if status[:log_start] == status[:log_end]
      Rails.logger.info "[Max3] No unread events"
      return
    end

    pages_read = 0
    addr = status[:log_start]
    while addr < status[:log_end]
      send_raw(read_log_page_packet(addr))
      page = recv_packet
      Rails.logger.info "[Max3] Page 0x#{addr.to_s(16).upcase}: #{hex_str(page)}"
      addr += 8
      pages_read += 1
    end

    Rails.logger.info "[Max3] Peek complete — #{pages_read} page(s), pointer unchanged"
    # No END_LOG sent — log pointer stays where it is
  end

  # Read all unread event log pages and import them as AccessEvent records.
  def fetch_event_log
    handshake!
    send_raw(END_SESSION)

    status_packet = recv_packet
    status = parse_status_response(status_packet)

    unless status
      Rails.logger.warn "[Max3] Unexpected response after END_SESSION: #{hex_str(status_packet)}"
      return
    end

    if status[:log_start] == status[:log_end]
      Rails.logger.info "[Max3] No new events (log_start == log_end == 0x#{status[:log_start].to_s(16).upcase})"
      return
    end

    pages_read = 0
    addr = status[:log_start]
    while addr < status[:log_end]
      send_raw(read_log_page_packet(addr))
      page = recv_packet
      process_log_page(page)
      addr += 8
      pages_read += 1
    end

    send_and_ack(END_LOG)
    send_raw(END_SESSION)
    recv_packet  # updated status with new log_start = old log_end

    Rails.logger.info "[Max3] Imported #{pages_read} log pages"
  end

  # Delete every slot that exists in the local database from the controller.
  # After completion all users are marked synced: false so the next sync
  # will re-add whichever ones are still active.
  #
  # Returns the number of slots deleted.
  def clear_all_users
    slots = User.pluck(:slot)
    raise "No users in database to clear" if slots.empty?

    handshake!

    slots.each do |slot|
      send_and_ack(delete_user_packet(slot))
      Rails.logger.info "[Max3] Cleared slot #{slot}"
    end

    send_raw(END_SESSION)
    User.update_all(synced: false)
    Rails.logger.info "[Max3] Cleared #{slots.size} slot(s) from controller"
    slots.size
  end

  # Walk every slot in the given range and send a delete packet for each one,
  # regardless of what the app database contains. Slots 1 and 2 are always
  # skipped (reserved master users). Does not read the database; marks all
  # existing DB users unsynced afterward. Returns the number of slots swept.
  def force_clear_all_users(first: 3, last: 2000)
    first = [first, 3].max  # never touch slots 1 or 2

    handshake!

    swept = 0
    (first..last).each do |slot|
      send_and_ack(delete_user_packet(slot))
      swept += 1
      Rails.logger.info "[Max3] Force-clear: slot #{slot}/#{last}" if swept % 100 == 0
    end

    send_raw(END_SESSION)
    User.update_all(synced: false)
    Rails.logger.info "[Max3] Force-clear complete — swept slots #{first}–#{last} (#{swept} packets)"
    swept
  end

  # Remove all standard-tier users from the controller and mark them synced: false.
  # Officers are untouched. Run sync_users afterward to restore access.
  # Returns the number of slots removed.
  def lockdown
    slots = User.standard.pluck(:slot)
    raise "No standard users in database" if slots.empty?

    handshake!

    slots.each do |slot|
      send_and_ack(delete_user_packet(slot))
      Rails.logger.info "[Max3] Lockdown: removed slot #{slot}"
    end

    send_raw(END_SESSION)
    User.standard.update_all(synced: false)
    Rails.logger.info "[Max3] Lockdown complete — #{slots.size} slot(s) removed"
    slots.size
  end

  # Request door status (contact state, REX, program mode).
  # Returns the raw 0x92 response payload hash, or nil on error.
  def door_status(door_number = 1)
    handshake!
    send_raw(door_query_packet(door_number))
    response = recv_packet
    send_raw(END_SESSION)

    payload = response[5..-3]
    return nil unless payload&.first == 0x92

    flags1 = payload[3]
    flags2 = payload[4]
    {
      door:          payload[2],
      program_mode:  flags1[0] == 1,
      door_closed:   flags1[4] == 1,
      rex_open:      flags2[0] == 1
    }
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  private

  def handshake!
    retries = 0
    begin
      send_raw(HANDSHAKE_1)
      status_packet = recv_packet    # 0x05 status/device info
      Rails.logger.debug "[Max3] Handshake status: #{hex_str(status_packet)}"

      send_raw(HANDSHAKE_2)
      ack = recv_packet              # 0x35 handshake ACK
      Rails.logger.debug "[Max3] Handshake ack: #{hex_str(ack)}"
    rescue RuntimeError => e
      raise unless e.message.include?("timeout") && retries < 1
      retries += 1
      Rails.logger.warn "[Max3] Handshake timeout, retrying..."
      sleep 0.5
      retry
    end
  end

  # Send a packet and wait for an ACK. Raises on invalid ACK.
  def send_and_ack(packet)
    send_raw(packet)
    ack = recv_packet
    unless valid_ack?(ack, packet)
      raise "Max3 ACK mismatch — sent #{hex_str(packet)}, got #{hex_str(ack)}"
    end
    ack
  end

  def send_raw(bytes)
    Rails.logger.debug "[Max3] TX: #{hex_str(bytes)}"
    @serial.write(bytes.pack("C*"))
  end

  # Read one complete packet from the controller.
  # Strategy: read 5-byte header+len first, then read len+2 more bytes (payload + CRC).
  def recv_packet
    deadline = Time.now + READ_TIMEOUT

    # Read until we see the 4-byte header [24 DB 02 00]
    buf = []
    loop do
      byte = read_byte(deadline)
      buf << byte
      if buf.last(4) == [0x24, 0xDB, 0x02, 0x00]
        break
      end
      if buf.length > 64
        raise "Max3 sync error — no header found in #{buf.length} bytes: #{hex_str(buf)}"
      end
    end

    len  = read_byte(deadline)
    rest = read_bytes(len + 2, deadline)  # payload + 2 CRC bytes

    packet = [0x24, 0xDB, 0x02, 0x00, len] + rest
    Rails.logger.debug "[Max3] RX: #{hex_str(packet)}"
    packet
  end

  def read_byte(deadline)
    loop do
      data = @serial.read(1)
      return data.unpack1("C") if data && data.length == 1
      raise "Max3 read timeout" if Time.now > deadline
      sleep 0.005
    end
  end

  def read_bytes(count, deadline)
    buf = []
    while buf.length < count
      data = @serial.read(count - buf.length)
      buf.concat(data.unpack("C*")) if data && data.length > 0
      raise "Max3 read timeout" if Time.now > deadline
      sleep 0.005 if data.nil? || data.empty?
    end
    buf
  end
end

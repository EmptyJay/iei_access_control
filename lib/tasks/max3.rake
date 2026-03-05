namespace :max3 do
  desc "Connect to the controller and print its status (handshake only)"
  task status: :environment do
    port = ENV.fetch("MAX3_PORT", Max3Session::DEFAULT_PORT)
    puts "Connecting to IEI Max3 on #{port}..."
    Max3Session.open(port) do |s|
      info = s.door_status(1)
      if info
        puts "Door #{info[:door]}:"
        puts "  Contact:      #{info[:door_closed] ? 'CLOSED' : 'OPEN'}"
        puts "  REX:          #{info[:rex_open] ? 'OPEN' : 'CLOSED'}"
        puts "  Program mode: #{info[:program_mode] ? 'ACTIVE' : 'off'}"
      else
        puts "Could not parse door status response."
      end
    end
  end

  desc "Sync pending users (added/deactivated) to the controller"
  task sync: :environment do
    pending = User.pending_sync.count
    puts "Pending changes: #{pending} user(s)"
    if pending.zero?
      puts "Nothing to sync."
      next
    end
    Max3Session.open do |s|
      s.sync_users
    end
    puts "Sync complete."
  end

  desc "Fetch event log from controller and import as AccessEvents"
  task fetch_log: :environment do
    before = AccessEvent.count
    Max3Session.open do |s|
      s.fetch_event_log
    end
    after = AccessEvent.count
    puts "Imported #{after - before} new event(s). Total: #{after}"
  end

  desc "Print rolling counter current value"
  task counter: :environment do
    val = Setting.rolling_counter
    puts "Rolling counter: 0x#{format('%02X', val)} (#{val})"
  end
end

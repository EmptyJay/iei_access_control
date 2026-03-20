namespace :max3 do
  def max3_run
    yield
  rescue RuntimeError => e
    abort "Max3 error: #{e.message}"
  end

  desc "Connect to the controller and print its status (handshake only)"
  task status: :environment do
    port = ENV.fetch("MAX3_PORT", Max3Session::DEFAULT_PORT)
    puts "Connecting to IEI Max3 on #{port}..."
    max3_run do
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
  end

  desc "Sync pending users (added/deactivated) to the controller"
  task sync: :environment do
    pending = User.pending_sync.count
    puts "Pending changes: #{pending} user(s)"
    if pending.zero?
      puts "Nothing to sync."
      next
    end
    max3_run do
      Max3Session.open do |s|
        s.sync_users
      end
    end
    puts "Sync complete."
  end

  desc "Peek at unread event log pages without advancing the pointer or writing to DB"
  task peek_log: :environment do
    max3_run do
      Max3Session.open do |s|
        s.peek_event_log
      end
    end
  end

  desc "Fetch event log from controller and import as AccessEvents"
  task fetch_log: :environment do
    before = AccessEvent.count
    max3_run do
      Max3Session.open do |s|
        s.fetch_event_log
      end
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

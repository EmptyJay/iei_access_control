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

  desc "Delete all users from the controller and mark them unsynced (use 'sync' to re-add active ones)"
  task clear_users: :environment do
    count = User.count
    if count.zero?
      puts "No users in database — nothing to clear."
      next
    end
    puts "WARNING: This will delete all #{count} user(s) from the controller."
    print "Type YES to continue: "
    input = $stdin.gets.to_s.strip
    unless input == "YES"
      puts "Aborted."
      next
    end
    max3_run do
      Max3Session.open do |s|
        cleared = s.clear_all_users
        puts "Cleared #{cleared} slot(s). Run 'rake max3:sync' to re-add active members."
      end
    end
  end

  desc "Remove all standard-tier users from controller (officers keep access). Run 'sync' to restore."
  task lockdown: :environment do
    officers = User.officer.count
    standard = User.standard.count
    if standard.zero?
      puts "No standard users — nothing to remove."
      next
    end
    puts "Officers keeping access: #{officers}"
    puts "WARNING: This will remove #{standard} standard user(s) from the controller."
    print "Type YES to continue: "
    input = $stdin.gets.to_s.strip
    unless input == "YES"
      puts "Aborted."
      next
    end
    max3_run do
      Max3Session.open do |s|
        removed = s.lockdown
        puts "Lockdown active — #{removed} user(s) removed. Run 'rake max3:sync' to restore access."
      end
    end
  end

  desc "Print rolling counter current value"
  task counter: :environment do
    val = Setting.rolling_counter
    puts "Rolling counter: 0x#{format('%02X', val)} (#{val})"
  end
end

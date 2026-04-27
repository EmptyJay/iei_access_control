namespace :backup do
  desc "Back up users and event log to a USB drive. Pass mount point as argument (default: /mnt/iei-backup)."
  task :usb, [:mount] => :environment do |_, args|
    require "csv"
    require "fileutils"

    mount = args[:mount] || "/mnt/iei-backup"
    abort "Mount point #{mount} does not exist" unless Dir.exist?(mount)

    # user.txt is required — unidentified drives take no action
    def parse_text_file(path)
      return nil unless File.exist?(path)
      File.readlines(path, chomp: true)
          .reject { |l| l.strip.start_with?("#") || l.strip.empty? }
          .first&.strip
    end

    actor = parse_text_file(File.join(mount, "user.txt"))
    unless actor.present?
      puts "ERROR: user.txt missing or contains no name — aborting."
      AccessEvent.create!(event_type: "backup_failed", occurred_at: Time.now, notes: nil)
      exit 1
    end
    puts "Drive owner: #{actor}"

    # Pull latest events from controller before snapshotting
    puts "Fetching event log from controller..."
    begin
      Max3Session.open { |s| s.fetch_event_log }
      puts "  Event log fetched."
    rescue => e
      puts "  WARNING: could not fetch event log — #{e.message}"
      puts "  Continuing backup with existing database records."
    end

    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    dest = File.join(mount, "iei-backup-#{timestamp}")
    FileUtils.mkdir_p(dest)
    puts "Writing backup to #{dest}"

    # Users CSV
    users_path = File.join(dest, "users.csv")
    CSV.open(users_path, "w", headers: true) do |csv|
      csv << %w[first_name last_name card_number site_code tier active slot]
      User.order(:last_name, :first_name).each do |u|
        csv << [u.first_name, u.last_name, u.card_number, u.site_code, u.tier, u.active, u.slot]
      end
    end
    puts "  users.csv    — #{User.count} record(s)"

    # Events CSV
    events_path = File.join(dest, "events.csv")
    CSV.open(events_path, "w", headers: true) do |csv|
      csv << %w[occurred_at event_type member notes]
      AccessEvent.order(:occurred_at).includes(:user).each do |e|
        csv << [e.occurred_at.strftime("%Y-%m-%d %H:%M"), e.event_type, e.user&.full_name, e.notes]
      end
    end
    puts "  events.csv   — #{AccessEvent.count} record(s)"

    # SQLite DB copy
    db_src = Rails.root.join("storage/production.sqlite3")
    if File.exist?(db_src)
      FileUtils.cp(db_src, File.join(dest, "production.sqlite3"))
      puts "  production.sqlite3 — #{(File.size(db_src) / 1024.0).round(1)} KB"
    else
      puts "  production.sqlite3 — not found, skipped"
    end

    puts "Backup complete: #{dest}"
    AccessEvent.create!(event_type: "backup", occurred_at: Time.now, notes: actor)

    # Lockdown control via system_state.txt
    control_file = File.join(mount, "system_state.txt")
    directive = parse_text_file(control_file)&.downcase

    if directive.nil?
      puts "No system_state.txt directive found, skipping lockdown control."
    else
      currently_locked = Setting["lockdown_active"] == "true"

      case directive
      when "lockdown"
        if currently_locked
          puts "Lockdown already active, no change."
        else
          puts "Initiating lockdown..."
          begin
            Max3Session.open { |s| s.lockdown }
            Setting["lockdown_active"] = "true"
            AccessEvent.create!(event_type: "lockdown", occurred_at: Time.now, notes: actor)
            puts "  Lockdown complete."
          rescue => e
            puts "  ERROR: lockdown failed — #{e.message}"
          end
        end
      when "normal"
        if currently_locked
          puts "Ending lockdown, restoring standard users..."
          begin
            Max3Session.open { |s| s.sync_users }
            Setting["lockdown_active"] = "false"
            AccessEvent.create!(event_type: "restore", occurred_at: Time.now, notes: actor)
            puts "  Restore complete."
          rescue => e
            puts "  ERROR: restore failed — #{e.message}"
          end
        else
          puts "Already in normal operation, no change."
        end
      else
        puts "WARNING: unrecognised directive '#{directive}' in system_state.txt, no action taken."
      end
    end
  end
end

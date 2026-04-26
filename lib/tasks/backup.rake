namespace :backup do
  desc "Back up users and event log to a USB drive. Pass mount point as argument (default: /mnt/iei-backup)."
  task :usb, [:mount] => :environment do |_, args|
    require "csv"
    require "fileutils"

    mount = args[:mount] || "/mnt/iei-backup"
    abort "Mount point #{mount} does not exist" unless Dir.exist?(mount)

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
      csv << %w[occurred_at event_type member]
      AccessEvent.order(:occurred_at).includes(:user).each do |e|
        csv << [e.occurred_at.strftime("%Y-%m-%d %H:%M"), e.event_type, e.user&.full_name]
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
  end
end

namespace :deploy do
  desc "Apply ERC-Update.bundle from USB drive. Called by usb_backup.sh after git fetch/merge."
  task :usb, [:mount] => :environment do |_, args|
    mount = args[:mount] || "/mnt/iei-backup"

    actor = begin
      id_file = File.join(mount, "user.txt")
      File.readlines(id_file, chomp: true)
          .reject { |l| l.strip.start_with?("#") || l.strip.empty? }
          .first&.strip if File.exist?(id_file)
    end

    puts "Running bundle install..."
    system("bundle install") or abort "bundle install failed"

    puts "Running db:migrate..."
    system("RAILS_ENV=production bin/rails db:migrate") or abort "db:migrate failed"

    puts "Running assets:precompile..."
    system("RAILS_ENV=production bin/rails assets:precompile") or abort "assets:precompile failed"

    AccessEvent.create!(event_type: "deploy", occurred_at: Time.current, notes: actor.presence)

    bundle = File.join(mount, "ERC-Update.bundle")
    File.delete(bundle) if File.exist?(bundle)
    puts "Deploy steps complete."
  end
end

# Seeds for IEI Access Control
#
# Run with: rails db:seed
#
# Two modes:
#   1. Seed from Hub Manager export file (set HUB_EXPORT env var to the file path)
#   2. Seed only the settings (rolling counter default)

# ── Settings ──────────────────────────────────────────────────────────────────

Setting.find_or_create_by!(key: "rolling_counter")   { |s| s.value = "D0"  }
Setting.find_or_create_by!(key: "default_site_code") { |s| s.value = "105" }
puts "Setting: rolling_counter = #{Setting['rolling_counter']}"

# ── Hub Manager Export Parser ─────────────────────────────────────────────────
#
# Fixed-width export format from Hub Manager. Column positions (0-indexed):
#   [0:5]     ID (Hub Manager DB id, not used for slot assignment)
#   [5:38]    Last, First name
#   [38:57]   Access Level
#   [57:68]   Visual ID = card number (decimal)
#   [68:75]   PIN (ignored)
#   [75:83]   RF Fob (ignored)
#   [83:93]   Card-Raw (hex, ignored — we re-encode from site+card)
#   [93:104]  Card (decimal duplicate of Visual ID)
#   [104:109] Site code (105 for all ERC members)
#   [127:135] Enabled (Yes/No)
#
# Slots are assigned sequentially starting from 3 (slots 1-2 are reserved).
# All imported users are marked synced: false — run sync_users afterward.
#
# Usage: HUB_EXPORT=/path/to/allusers.txt RAILS_ENV=production bin/rails db:seed

export_file = ENV["HUB_EXPORT"]

unless export_file
  puts "Skipping member import (set HUB_EXPORT=/path/to/allusers.txt to import members)."
  return
end

unless File.exist?(export_file)
  abort "ERROR: HUB_EXPORT file not found: #{export_file}"
end

imported = 0
skipped  = 0
errors   = 0

File.foreach(export_file) do |line|
  s = line.chomp
  next if s.length < 68

  card_number = s[57, 11].strip.to_i
  next if card_number.zero?

  raw_name  = s[5, 33].strip
  next if raw_name.empty?

  site_code = s[104, 5].strip.to_i
  next if site_code.zero?

  last_name, first_name = raw_name.split(", ", 2)
  first_name = first_name.to_s.strip
  last_name  = last_name.to_s.strip

  if User.exists?(card_number: card_number)
    puts "  SKIP #{raw_name} (card #{card_number}) — already exists"
    skipped += 1
    next
  end

  begin
    User.create!(
      slot:        User.next_available_slot,
      first_name:  first_name,
      last_name:   last_name,
      site_code:   site_code,
      card_number: card_number,
      active:      true,
      synced:      false
    )
    imported += 1
    print "." if (imported % 25).zero?
  rescue ActiveRecord::RecordInvalid => e
    puts "\n  ERROR #{raw_name} (card #{card_number}): #{e.message}"
    errors += 1
  end
end

puts "\n\nImport complete: #{imported} imported, #{skipped} skipped, #{errors} errors."
puts "Total users: #{User.count}"

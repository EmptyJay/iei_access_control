# Seeds for IEI Access Control
#
# Run with: rails db:seed
#
# Two modes:
#   1. Seed from Hub Manager export file (set HUB_EXPORT env var to the file path)
#   2. Seed only the settings (rolling counter default)

# ── Settings ──────────────────────────────────────────────────────────────────

Setting.find_or_create_by!(key: "rolling_counter") { |s| s.value = "D0" }
puts "Setting: rolling_counter = #{Setting['rolling_counter']}"

# ── Hub Manager Export Parser ─────────────────────────────────────────────────
#
# Export format (tab-separated):
#   [slot]  [name]  [group]  [card_num]  [internal_value]  [card_num_dup]  [site_code]  [tz]  ...
#
# Example line:
#   476	Shiffer, Joe	ERC Members	51770	0004D39475	51770	105	0	0	0	No	Yes
#
# Usage: HUB_EXPORT=/path/to/export.txt rails db:seed

export_file = ENV["HUB_EXPORT"]

unless export_file
  puts "Skipping member import (set HUB_EXPORT=/path/to/export.txt to import members)."
  return
end

unless File.exist?(export_file)
  abort "ERROR: HUB_EXPORT file not found: #{export_file}"
end

imported = 0
skipped  = 0
errors   = 0

File.foreach(export_file) do |line|
  cols = line.chomp.split("\t")
  next if cols.length < 7          # skip blank/header lines

  slot        = cols[0].strip.to_i
  name        = cols[1].strip
  card_number = cols[3].strip.to_i
  site_code   = cols[6].strip.to_i

  next if slot.zero? || name.empty? || card_number.zero?

  if User.exists?(slot: slot)
    puts "  SKIP slot #{slot} (#{name}) — already exists"
    skipped += 1
    next
  end

  begin
    User.create!(
      slot:        slot,
      name:        name,
      site_code:   site_code,
      card_number: card_number,
      active:      true,
      synced:      true   # already programmed in the controller
    )
    imported += 1
    print "." if (imported % 50).zero?
  rescue ActiveRecord::RecordInvalid => e
    puts "\n  ERROR slot #{slot} (#{name}): #{e.message}"
    errors += 1
  end
end

puts "\n\nImport complete: #{imported} imported, #{skipped} skipped, #{errors} errors."
puts "Total users: #{User.count}"

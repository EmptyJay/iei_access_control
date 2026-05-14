class Setting < ApplicationRecord
  validates :key,   presence: true, uniqueness: true
  validates :value, presence: true

  # Setting["rolling_counter"]  => "D0"
  # Setting["rolling_counter"] = "D1"
  def self.[](key)
    find_by(key: key)&.value
  end

  def self.[]=(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value.to_s
    record.save!
  end

  # Returns current rolling counter as an integer (0x0000..0xFFFF).
  def self.rolling_counter
    (self["rolling_counter"] || "15D0").to_i(16)
  end

  # Increments the counter (wrapping 0xFFFF -> 0x0000) and persists it.
  # Returns the value that was consumed (before increment) as an integer.
  def self.increment_counter!
    current = rolling_counter
    self["rolling_counter"] = format("%04X", (current + 1) & 0xFFFF)
    current
  end
end

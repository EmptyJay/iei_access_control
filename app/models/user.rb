class User < ApplicationRecord
  has_many :access_events, dependent: :nullify

  validates :first_name,  presence: true
  validates :last_name,   presence: true
  validates :slot,        presence: true, uniqueness: true, numericality: { only_integer: true, greater_than: 0 }
  validates :card_number, presence: true, uniqueness: true, numericality: { only_integer: true, greater_than: 0 }
  validates :site_code,   presence: true, numericality: { only_integer: true }

  TIERS = %w[standard officer].freeze

  validates :tier, inclusion: { in: TIERS }

  scope :active,       -> { where(active: true) }
  scope :inactive,     -> { where(active: false) }
  scope :pending_sync, -> { where(synced: false) }
  scope :standard,     -> { where(tier: "standard") }
  scope :officer,      -> { where(tier: "officer") }

  def full_name
    "#{first_name} #{last_name}"
  end

  # Returns the next available Hub Manager User ID slot (5001+).
  # Existing members imported from Hub Manager have slots in the 5000+ range.
  # New members added via the web UI are assigned the next slot above the current maximum.
  def self.next_available_slot
    max = order(:slot).pluck(:slot).select { |s| s >= 5001 }.max
    (max || 5000) + 1
  end
end

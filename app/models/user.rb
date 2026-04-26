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

  # Returns the next available controller slot (3+, skipping reserved slots 1-2).
  # Slots are small sequential integers matching the controller's physical slot addresses.
  def self.next_available_slot
    max = maximum(:slot) || 2
    [max + 1, 3].max
  end
end

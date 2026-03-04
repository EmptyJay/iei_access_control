class User < ApplicationRecord
  has_many :access_events, dependent: :nullify

  validates :first_name,  presence: true
  validates :last_name,   presence: true
  validates :slot,        presence: true, uniqueness: true, numericality: { only_integer: true, greater_than: 0 }
  validates :card_number, presence: true, uniqueness: true, numericality: { only_integer: true, greater_than: 0 }
  validates :site_code,   presence: true, numericality: { only_integer: true }

  scope :active,       -> { where(active: true) }
  scope :inactive,     -> { where(active: false) }
  scope :pending_sync, -> { where(synced: false) }

  def full_name
    "#{first_name} #{last_name}"
  end

  # Returns the lowest integer slot number not currently in use.
  def self.next_available_slot
    used = order(:slot).pluck(:slot)
    candidate = 1
    used.each do |s|
      break if s > candidate
      candidate = s + 1
    end
    candidate
  end
end

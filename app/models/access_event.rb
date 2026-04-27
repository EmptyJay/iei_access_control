class AccessEvent < ApplicationRecord
  belongs_to :user, optional: true

  validates :event_type,  presence: true
  validates :occurred_at, presence: true

  scope :recent,   -> { order(occurred_at: :desc) }
  scope :granted,  -> { where(event_type: "granted") }
  scope :denied,   -> { where(event_type: "denied") }

  HUMAN_TYPES = {
    "granted"       => "Access Granted",
    "denied"        => "Access Denied",
    "backup"        => "USB Backup",
    "backup_failed" => "USB Backup Failed",
    "lockdown"      => "Lockdown Initiated",
    "restore"       => "Lockdown Ended"
  }.freeze

  def human_event_type
    HUMAN_TYPES.fetch(event_type) { event_type.humanize }
  end
end

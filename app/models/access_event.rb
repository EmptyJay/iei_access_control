class AccessEvent < ApplicationRecord
  belongs_to :user,  optional: true
  belongs_to :admin, optional: true

  validates :event_type,  presence: true
  validates :occurred_at, presence: true

  scope :recent,  -> { order(occurred_at: :desc) }
  scope :granted, -> { where(event_type: "granted") }
  scope :denied,  -> { where(event_type: "denied") }

  HUMAN_TYPES = {
    "granted"          => "Access Granted",
    "denied"           => "Access Denied",
    "backup"           => "USB Backup",
    "backup_failed"    => "USB Backup Failed",
    "lockdown"         => "Lockdown Initiated",
    "restore"          => "Lockdown Ended",
    "deploy"           => "App Updated",
    "deploy_failed"    => "Update Failed",
    "sync"             => "Controller Sync",
    "clear"            => "Controller Cleared",
    "member_created"   => "Member Added",
    "member_updated"   => "Member Updated",
    "member_deleted"   => "Member Deleted",
    "members_imported" => "Members Imported",
    "members_bulk"     => "Bulk Member Update",
    "settings_changed" => "Settings Changed"
  }.freeze

  def human_event_type
    HUMAN_TYPES.fetch(event_type) { event_type.humanize }
  end
end

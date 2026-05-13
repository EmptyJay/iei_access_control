class Admin < ApplicationRecord
  has_secure_password
  has_many :access_events

  ROLES = %w[admin viewer].freeze

  validates :name,     presence: true
  validates :username, presence: true, uniqueness: { case_sensitive: false }
  validates :role,     inclusion: { in: ROLES }

  scope :active, -> { where(active: true) }

  def admin?
    role == "admin"
  end

  def viewer?
    role == "viewer"
  end
end

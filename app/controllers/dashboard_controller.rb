class DashboardController < ApplicationController
  def index
    @total_members   = User.count
    @active_members  = User.active.count
    @inactive_members = User.inactive.count
    @pending_sync    = User.pending_sync.count
    @recent_events   = AccessEvent.recent.includes(:user).limit(10)
  end
end

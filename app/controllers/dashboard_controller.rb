class DashboardController < ApplicationController
  before_action :require_admin_role, except: [ :index ]

  def index
    @total_members    = User.count
    @active_members   = User.active.count
    @inactive_members = User.inactive.count
    @pending_sync     = User.pending_sync.count
    @officer_count    = User.officer.count
    @standard_count   = User.standard.count
    @lockdown_active  = Setting["lockdown_active"] == "true"
    @recent_events    = AccessEvent.recent.includes(:user, :admin).limit(10)
  end

  def sync_users
    Max3Session.open { |s| s.sync_users }
    log_admin_action("sync")
    redirect_to root_path, notice: "Sync complete."
  rescue => e
    redirect_to root_path, alert: "Sync failed: #{e.message}"
  end

  def lockdown
    removed = nil
    Max3Session.open { |s| removed = s.lockdown }
    Setting["lockdown_active"] = "true"
    log_admin_action("lockdown", notes: "#{removed} standard member(s) removed")
    redirect_to root_path, notice: "Lockdown active — #{removed} standard member(s) removed from controller."
  rescue => e
    redirect_to root_path, alert: "Lockdown failed: #{e.message}"
  end

  def restore
    Max3Session.open { |s| s.sync_users }
    Setting["lockdown_active"] = "false"
    log_admin_action("restore")
    redirect_to root_path, notice: "Access restored — standard members re-added to controller."
  rescue => e
    redirect_to root_path, alert: "Restore failed: #{e.message}"
  end

  def clear_users
    removed = nil
    Max3Session.open { |s| removed = s.clear_all_users }
    Setting["lockdown_active"] = "false"
    log_admin_action("clear", notes: "#{removed} slot(s) cleared")
    redirect_to root_path, notice: "Controller cleared — #{removed} slot(s) removed. All members marked unsynced."
  rescue => e
    redirect_to root_path, alert: "Clear failed: #{e.message}"
  end

  def force_clear_users
    swept = nil
    Max3Session.open { |s| swept = s.force_clear_all_users }
    Setting["lockdown_active"] = "false"
    log_admin_action("clear", notes: "Force-clear: #{swept} slot(s) swept")
    redirect_to root_path, notice: "Force-clear complete — #{swept} slot(s) swept. All members marked unsynced."
  rescue => e
    redirect_to root_path, alert: "Force-clear failed: #{e.message}"
  end
end

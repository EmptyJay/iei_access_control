class DashboardController < ApplicationController
  include ActionController::Live

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

  def sync_stream
    stream_operation do |sse|
      total = User.pending_sync.active.count + User.pending_sync.inactive.count
      sse.write({ message: "Syncing #{total} member(s)…", current: 0, total: total }, event: "progress")
      Max3Session.open { |s| s.sync_users { |n, t, msg| sse.write({ message: msg, current: n, total: t }, event: "progress") } }
      log_admin_action("sync")
      "Sync complete."
    end
  end

  def lockdown_stream
    stream_operation do |sse|
      total = User.standard.count
      sse.write({ message: "Initiating lockdown…", current: 0, total: total }, event: "progress")
      removed = nil
      Max3Session.open { |s| removed = s.lockdown { |n, t, msg| sse.write({ message: msg, current: n, total: t }, event: "progress") } }
      Setting["lockdown_active"] = "true"
      log_admin_action("lockdown", notes: "#{removed} standard member(s) removed")
      "Lockdown active — #{removed} standard member(s) removed."
    end
  end

  def restore_stream
    stream_operation do |sse|
      total = User.pending_sync.active.count
      sse.write({ message: "Restoring access for #{total} member(s)…", current: 0, total: total }, event: "progress")
      Max3Session.open { |s| s.sync_users { |n, t, msg| sse.write({ message: msg, current: n, total: t }, event: "progress") } }
      Setting["lockdown_active"] = "false"
      log_admin_action("restore")
      "Access restored."
    end
  end

  def clear_stream
    stream_operation do |sse|
      total = User.count
      sse.write({ message: "Clearing #{total} member(s) from controller…", current: 0, total: total }, event: "progress")
      removed = nil
      Max3Session.open { |s| removed = s.clear_all_users { |n, t, msg| sse.write({ message: msg, current: n, total: t }, event: "progress") } }
      Setting["lockdown_active"] = "false"
      log_admin_action("clear", notes: "#{removed} slot(s) cleared")
      "Controller cleared — #{removed} slot(s) removed."
    end
  end

  def force_clear_stream
    stream_operation do |sse|
      sse.write({ message: "Force-clearing all 1998 slots…", current: 0, total: 1998 }, event: "progress")
      swept = nil
      Max3Session.open { |s| swept = s.force_clear_all_users { |n, t, msg| sse.write({ message: msg, current: n, total: t }, event: "progress") } }
      Setting["lockdown_active"] = "false"
      log_admin_action("clear", notes: "Force-clear: #{swept} slot(s) swept")
      "Force-clear complete — #{swept} slot(s) swept."
    end
  end

  private

  def stream_operation
    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    sse = ActionController::Live::SSE.new(response.stream, retry: 5000)
    begin
      notice = yield(sse)
      sse.write({ notice: notice }, event: "done")
    rescue => e
      sse.write({ error: e.message }, event: "failure")
    ensure
      sse.close
    end
  end
end

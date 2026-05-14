class SettingsController < ApplicationController
  before_action :require_admin_role, only: [ :update, :purge_debug_log ]

  def edit
    @default_site_code   = Setting["default_site_code"] || "105"
    @rolling_counter_hex = Setting["rolling_counter"] || "15D0"
    @rolling_counter_dec = @rolling_counter_hex.to_i(16)
    @max3_debug          = Setting["max3_debug"] == "true"
    @debug_log_path      = Rails.root.join("log/max3_debug.log")
    @debug_log_size      = File.exist?(@debug_log_path) ? File.size(@debug_log_path) : nil
  end

  def update
    site_code  = params[:default_site_code].to_s.strip
    max3_debug = params[:max3_debug] == "1" ? "true" : "false"

    unless site_code.match?(/\A\d+\z/)
      flash.now[:alert] = "Site code must be a number."
      return render :edit, status: :unprocessable_entity
    end

    changes = []
    changes << "default_site_code = #{site_code}" if site_code != (Setting["default_site_code"] || "105")
    changes << "max3_debug = #{max3_debug}"        if max3_debug != (Setting["max3_debug"] || "false")

    Setting["default_site_code"] = site_code
    Setting["max3_debug"]        = max3_debug

    log_admin_action("settings_changed", notes: changes.join(", ")) if changes.any?
    redirect_to edit_settings_path, notice: "Settings saved."
  end

  def purge_debug_log
    FileUtils.rm_f(Rails.root.join("log/max3_debug.log"))
    redirect_to edit_settings_path, notice: "Debug log purged."
  end
end

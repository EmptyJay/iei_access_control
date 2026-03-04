class SettingsController < ApplicationController
  def edit
    @default_site_code  = Setting["default_site_code"] || "105"
    @rolling_counter_hex = Setting["rolling_counter"] || "D0"
    @rolling_counter_dec = @rolling_counter_hex.to_i(16)
  end

  def update
    site_code = params[:default_site_code].to_s.strip
    if site_code.match?(/\A\d+\z/)
      Setting["default_site_code"] = site_code
      redirect_to edit_settings_path, notice: "Settings saved."
    else
      flash.now[:alert] = "Site code must be a number."
      render :edit, status: :unprocessable_entity
    end
  end
end

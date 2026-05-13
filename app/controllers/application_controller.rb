class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :require_login

  helper_method :current_admin, :logged_in?

  private

  def current_admin
    @current_admin ||= Admin.find_by(id: session[:admin_id])
  end

  def logged_in?
    current_admin.present?
  end

  def require_login
    return redirect_to setup_path if Admin.none?
    redirect_to login_path unless logged_in?
  end

  def require_admin_role
    redirect_to root_path, alert: "Not authorized." unless current_admin&.admin?
  end

  def log_admin_action(event_type, notes: nil, user: nil)
    AccessEvent.create!(
      event_type:  event_type,
      occurred_at: Time.current,
      admin_id:    current_admin&.id,
      user_id:     user&.id,
      notes:       notes
    )
  end
end

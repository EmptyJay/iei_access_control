class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :require_login

  private

  def require_login
    redirect_to login_path unless logged_in?
  end

  def logged_in?
    session[:authenticated] == true
  end
  helper_method :logged_in?
end

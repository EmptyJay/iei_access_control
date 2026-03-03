class SessionsController < ApplicationController
  skip_before_action :require_login

  def new
    redirect_to users_path if logged_in?
  end

  def create
    digest = Rails.application.credentials.admin_password_digest
    if BCrypt::Password.new(digest) == params[:password]
      session[:authenticated] = true
      redirect_to users_path, notice: "Logged in."
    else
      flash.now[:alert] = "Invalid password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:authenticated)
    redirect_to login_path, notice: "Logged out."
  end
end

class SetupController < ApplicationController
  skip_before_action :require_login
  before_action :redirect_if_admins_exist

  def new
    @admin = Admin.new
  end

  def create
    @admin = Admin.new(setup_params.merge(role: "admin", active: true))
    if @admin.save
      session[:admin_id] = @admin.id
      redirect_to root_path, notice: "Admin account created. Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_admins_exist
    redirect_to logged_in? ? root_path : login_path unless Admin.none?
  end

  def setup_params
    params.expect(admin: [ :name, :username, :password, :password_confirmation ])
  end
end

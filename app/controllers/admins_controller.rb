class AdminsController < ApplicationController
  before_action :require_admin_role
  before_action :set_admin, only: [ :edit, :update ]

  def index
    @admins = Admin.order(:name)
  end

  def new
    @admin = Admin.new
  end

  def create
    @admin = Admin.new(admin_params)
    if @admin.save
      redirect_to admins_path, notice: "#{@admin.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = admin_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @admin.update(attrs)
      redirect_to admins_path, notice: "#{@admin.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_admin
    @admin = Admin.find(params[:id])
  end

  def admin_params
    params.expect(admin: [ :name, :username, :role, :active, :password, :password_confirmation ])
  end
end

class UsersController < ApplicationController
  before_action :set_user, only: [ :edit, :update, :destroy ]

  def index
    @users = User.order(:slot)
  end

  def new
    @user = User.new(slot: User.next_available_slot, site_code: 105)
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to users_path, notice: "#{@user.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      @user.update_column(:synced, false) if @user.previous_changes.except("synced", "updated_at").any?
      redirect_to users_path, notice: "#{@user.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to users_path, notice: "#{@user.name} removed."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.expect(user: [ :name, :slot, :site_code, :card_number, :active ])
  end
end

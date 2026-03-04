class UsersController < ApplicationController
  before_action :set_user, only: [ :edit, :update, :destroy ]

  SORTABLE_COLUMNS = %w[first_name last_name card_number active synced].freeze

  def index
    @sort      = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : "last_name"
    @direction = params[:direction] == "desc" ? "desc" : "asc"
    @users     = User.order("#{@sort} #{@direction}")
  end

  def new
    @user = User.new(slot: User.next_available_slot, site_code: 105)
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to users_path, notice: "#{@user.full_name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      @user.update_column(:synced, false) if @user.previous_changes.except("synced", "updated_at").any?
      redirect_to users_path, notice: "#{@user.full_name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to users_path, notice: "#{@user.full_name} removed."
  end

  def export
    require "csv"
    csv = CSV.generate(headers: true) do |rows|
      rows << %w[first_name last_name card_number site_code active slot synced]
      User.order(:last_name, :first_name).each do |user|
        rows << [ user.first_name, user.last_name, user.card_number,
                  user.site_code, user.active, user.slot, user.synced ]
      end
    end
    send_data csv, filename: "members-#{Date.today}.csv", type: "text/csv", disposition: "attachment"
  end

  def import_form
  end

  def import
    unless params[:file].present?
      flash.now[:alert] = "Please choose a CSV file."
      return render :import_form, status: :unprocessable_entity
    end

    @results = { imported: [], skipped: [], errors: [] }

    require "csv"
    csv = CSV.parse(params[:file].read, headers: true, skip_blanks: true)

    unless (csv.headers & %w[first_name last_name card_number]).length == 3
      flash.now[:alert] = "CSV must have headers: first_name, last_name, card_number (and optionally site_code, active)."
      return render :import_form, status: :unprocessable_entity
    end

    csv.each.with_index(2) do |row, line|
      first_name  = row["first_name"].to_s.strip
      last_name   = row["last_name"].to_s.strip
      card_number = row["card_number"].to_s.strip.to_i
      site_code   = row["site_code"].present? ? row["site_code"].strip.to_i : 105
      active      = row["active"].blank? || row["active"].strip.downcase != "false"
      display     = "#{first_name} #{last_name}".strip

      if User.exists?(card_number: card_number)
        @results[:skipped] << { line: line, name: display, reason: "card number #{card_number} already exists" }
        next
      end

      user = User.new(first_name: first_name, last_name: last_name,
                      card_number: card_number, site_code: site_code,
                      active: active, slot: User.next_available_slot)

      if user.save
        @results[:imported] << { line: line, name: display }
      else
        @results[:errors] << { line: line, name: display, messages: user.errors.full_messages }
      end
    end

    render :import_results
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.expect(user: [ :first_name, :last_name, :slot, :site_code, :card_number, :active ])
  end
end

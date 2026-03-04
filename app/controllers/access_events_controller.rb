class AccessEventsController < ApplicationController
  def index
    @events = AccessEvent.recent.includes(:user)

    if params[:event_type].present? && AccessEvent::HUMAN_TYPES.key?(params[:event_type])
      @events = @events.where(event_type: params[:event_type])
    end

    @range = params[:range] || "week"
    @events = case @range
    when "today" then @events.where(occurred_at: Time.zone.today.all_day)
    when "week"  then @events.where(occurred_at: 1.week.ago..)
    when "month" then @events.where(occurred_at: 1.month.ago..)
    else @events
    end

    @total  = @events.count
    @events = @events.limit(500)
  end
end

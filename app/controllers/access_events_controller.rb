class AccessEventsController < ApplicationController
  def fetch
    Max3Session.open { |s| s.fetch_event_log }
    redirect_to access_events_path, notice: "Event log retrieved."
  rescue => e
    redirect_to access_events_path, alert: "Failed to retrieve log: #{e.message}"
  end

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

class AccessEventsController < ApplicationController
  def fetch
    Max3Session.open { |s| s.fetch_event_log }
    redirect_to access_events_path, notice: "Event log retrieved."
  rescue => e
    redirect_to access_events_path, alert: "Failed to retrieve log: #{e.message}"
  end

  def index
    @events = filtered_events(params[:range] || "week")
    @range  = params[:range] || "week"
    @total  = @events.count
    @events = @events.limit(500)
  end

  def export
    require "csv"
    events = filtered_events(params[:range] || "all")
    range_label = params[:range] || "all"

    csv = CSV.generate(headers: true) do |rows|
      rows << %w[occurred_at event_type member]
      events.each do |e|
        rows << [ e.occurred_at.strftime("%Y-%m-%d %H:%M"), e.event_type, e.user&.full_name ]
      end
    end

    send_data csv, filename: "events-#{range_label}-#{Date.today}.csv",
                   type: "text/csv", disposition: "attachment"
  end

  private

  def filtered_events(range)
    events = AccessEvent.recent.includes(:user)

    if params[:event_type].present? && AccessEvent::HUMAN_TYPES.key?(params[:event_type])
      events = events.where(event_type: params[:event_type])
    end

    case range
    when "today" then events.where(occurred_at: Time.zone.today.all_day)
    when "week"  then events.where(occurred_at: 1.week.ago..)
    when "month" then events.where(occurred_at: 1.month.ago..)
    else events
    end
  end
end

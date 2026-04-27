module AccessEventsHelper
  BADGE_CLASSES = {
    "granted"       => "bg-success",
    "denied"        => "bg-danger",
    "backup"        => "bg-secondary",
    "backup_failed" => "bg-danger",
    "lockdown"      => "bg-warning text-dark",
    "restore"       => "bg-info text-dark"
  }.freeze

  def event_type_badge(event)
    css = BADGE_CLASSES.fetch(event.event_type, "bg-secondary")
    content_tag(:span, event.human_event_type, class: "badge #{css}")
  end
end

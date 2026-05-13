module AccessEventsHelper
  BADGE_CLASSES = {
    "granted"          => "bg-success",
    "denied"           => "bg-danger",
    "backup"           => "bg-secondary",
    "backup_failed"    => "bg-danger",
    "lockdown"         => "bg-warning text-dark",
    "restore"          => "bg-info text-dark",
    "deploy"           => "bg-primary",
    "deploy_failed"    => "bg-danger",
    "sync"             => "bg-primary",
    "clear"            => "bg-warning text-dark",
    "member_created"   => "bg-success",
    "member_updated"   => "bg-info text-dark",
    "member_deleted"   => "bg-danger",
    "members_imported" => "bg-success",
    "members_bulk"     => "bg-info text-dark",
    "settings_changed" => "bg-secondary"
  }.freeze

  def event_type_badge(event)
    css = BADGE_CLASSES.fetch(event.event_type, "bg-secondary")
    content_tag(:span, event.human_event_type, class: "badge #{css}")
  end
end

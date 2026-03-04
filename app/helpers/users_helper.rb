module UsersHelper
  def sort_link(label, column)
    is_active  = @sort == column
    next_dir   = is_active && @direction == "asc" ? "desc" : "asc"
    icon       = is_active ? " <i class=\"bi bi-arrow-#{@direction == 'asc' ? 'up' : 'down'}\"></i>" : ""
    link_to (label + icon).html_safe, users_path(sort: column, direction: next_dir),
            class: "text-white text-decoration-none"
  end
end

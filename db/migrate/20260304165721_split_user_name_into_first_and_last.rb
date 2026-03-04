class SplitUserNameIntoFirstAndLast < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :first_name, :string
    add_column :users, :last_name,  :string

    # Existing names are in "Last, First" format from Hub Manager export.
    # Split them; if no comma, treat the whole string as last_name.
    User.find_each do |user|
      last, first = user.name.split(", ", 2)
      user.update_columns(last_name: last.to_s.strip, first_name: first.to_s.strip)
    end

    change_column_null :users, :first_name, false
    change_column_null :users, :last_name,  false
    remove_column :users, :name
  end

  def down
    add_column :users, :name, :string

    User.find_each do |user|
      full = [ user.last_name, user.first_name ].reject(&:blank?).join(", ")
      user.update_column(:name, full)
    end

    change_column_null :users, :name, false
    remove_column :users, :first_name
    remove_column :users, :last_name
  end
end

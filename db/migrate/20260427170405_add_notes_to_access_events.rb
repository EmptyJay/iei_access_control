class AddNotesToAccessEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :access_events, :notes, :string
  end
end

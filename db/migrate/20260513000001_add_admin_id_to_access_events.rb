class AddAdminIdToAccessEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :access_events, :admin, foreign_key: true, null: true
  end
end

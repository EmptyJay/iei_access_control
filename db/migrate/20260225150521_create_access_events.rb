class CreateAccessEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :access_events do |t|
      t.references :user, foreign_key: true, null: true  # null for denied/system events
      t.string   :event_type,  null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :access_events, :occurred_at
  end
end

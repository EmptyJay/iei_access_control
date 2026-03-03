class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :name,        null: false
      t.integer :slot,        null: false
      t.integer :site_code,   null: false, default: 105
      t.integer :card_number, null: false
      t.boolean :active,      null: false, default: true
      t.boolean :synced,      null: false, default: false

      t.timestamps
    end

    add_index :users, :slot,        unique: true
    add_index :users, :card_number, unique: true
  end
end

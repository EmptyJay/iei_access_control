class CreateAdmins < ActiveRecord::Migration[8.0]
  def change
    create_table :admins do |t|
      t.string :name, null: false
      t.string :username, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "admin"
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :admins, :username, unique: true
  end
end

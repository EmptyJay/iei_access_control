class AddTierToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :tier, :string, null: false, default: "standard"
    add_index :users, :tier
  end
end

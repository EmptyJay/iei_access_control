class AddWriteCounterToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :write_counter, :integer
    add_index  :users, :write_counter
  end
end

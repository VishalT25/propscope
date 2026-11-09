class AddAdminAndOddsFormatToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, null: false, default: false
    add_column :users, :odds_format, :string, null: false, default: "american"
  end
end

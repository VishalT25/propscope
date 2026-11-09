class AddImageUrls < ActiveRecord::Migration[8.1]
  def change
    # Optional. When blank we draw our own monogram badges. Self-hosters with licensed images can set these.
    add_column :teams, :logo_url, :string
    add_column :players, :photo_url, :string
    add_column :bookmakers, :logo_url, :string
  end
end

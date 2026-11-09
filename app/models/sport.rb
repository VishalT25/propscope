class Sport < ApplicationRecord
  has_many :teams, dependent: :destroy
  has_many :players, dependent: :destroy
  has_many :games, dependent: :destroy

  validates :key, :name, presence: true
  validates :key, uniqueness: true

  def self.nba = find_or_create_by!(key: "nba") { |s| s.name = "NBA" }
end

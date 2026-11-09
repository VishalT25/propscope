class Team < ApplicationRecord
  belongs_to :sport
  has_many :players, dependent: :nullify

  validates :abbreviation, :name, presence: true
  validates :abbreviation, uniqueness: { scope: :sport_id, case_sensitive: false }
end

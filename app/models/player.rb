class Player < ApplicationRecord
  belongs_to :sport
  belongs_to :team, optional: true
  has_many :game_logs, class_name: "PlayerGameLog", dependent: :destroy
  has_one_attached :photo # an uploaded photo (see Images::Attach); photo_url points at it

  before_validation { self.normalized_name = NameNormalizer.call("#{first_name} #{last_name}") }

  validates :first_name, :last_name, presence: true

  def full_name = "#{first_name} #{last_name}"
end

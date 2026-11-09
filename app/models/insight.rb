class Insight < ApplicationRecord
  belongs_to :subject, polymorphic: true
  belongs_to :game, optional: true
  belongs_to :market, optional: true

  validates :rule_key, :statement, :computed_at, presence: true
end

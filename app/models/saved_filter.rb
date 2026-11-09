class SavedFilter < ApplicationRecord
  belongs_to :user
  validates :name, presence: true
  validates :scope, inclusion: { in: %w[props ev] }
end

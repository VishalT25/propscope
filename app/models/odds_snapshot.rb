# Append-only: prices and lines are never updated. Only metadata may change: is_closing (last pre-tip row) and the book's deeplink.
class OddsSnapshot < ApplicationRecord
  OUTCOMES = %w[over under home away].freeze

  belongs_to :market
  belongs_to :bookmaker

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :american_odds, :decimal_odds, :captured_at, :source_provider, presence: true

  before_update do
    illegal = changed - %w[is_closing deeplink updated_at]
    raise ActiveRecord::ReadOnlyRecord, "odds_snapshots are append-only (tried to change #{illegal.join(', ')})" if illegal.any?
  end

  scope :latest_per_outcome, lambda {
    select("DISTINCT ON (odds_snapshots.market_id, odds_snapshots.outcome, odds_snapshots.bookmaker_id) odds_snapshots.*")
      .order("odds_snapshots.market_id, odds_snapshots.outcome, odds_snapshots.bookmaker_id, odds_snapshots.captured_at DESC")
  }
end

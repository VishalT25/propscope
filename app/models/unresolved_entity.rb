class UnresolvedEntity < ApplicationRecord
  validates :provider, :external_type, :external_id, :reason, presence: true

  scope :open, -> { where(resolved_at: nil) }

  def self.record!(provider:, type:, external_id:, payload:, reason:)
    row = find_or_initialize_by(provider: provider, external_type: type, external_id: external_id.to_s)
    row.update!(payload: payload, reason: reason, resolved_at: nil)
    row
  end

  def resolve!(time = Time.current) = update!(resolved_at: time)
end

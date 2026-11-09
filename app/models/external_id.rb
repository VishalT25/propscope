class ExternalId < ApplicationRecord
  belongs_to :internal, polymorphic: true, foreign_key: :internal_id, foreign_type: :internal_type

  validates :provider, :external_type, :external_id, presence: true

  def self.lookup(provider, type, external_id)
    find_by(provider: provider, external_type: type, external_id: external_id.to_s)&.internal
  end

  # Bulk lookup: { external_id => internal_id } for one provider/type, in a single query.
  def self.internal_ids(provider, type, external_ids)
    where(provider: provider, external_type: type, external_id: external_ids.map(&:to_s).uniq).pluck(:external_id, :internal_id).to_h
  end

  def self.register!(provider, type, external_id, record)
    row = find_or_initialize_by(provider: provider, external_type: type, external_id: external_id.to_s)
    row.internal = record
    row.save!
    row
  end
end

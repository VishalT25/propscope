class RawPayload < ApplicationRecord
  RETENTION = 14.days

  validates :provider, :endpoint, :params_digest, :fetched_at, :status, :body_sha256, presence: true

  scope :expired, ->(now = Time.current) { where(fetched_at: ...(now - RETENTION)) }
end

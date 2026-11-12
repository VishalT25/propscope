class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :saved_filters, dependent: :destroy
  has_many :picks, dependent: :destroy
  has_many :slips, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :odds_format, inclusion: { in: ->(_) { Rails.configuration.x.odds_formats } }
  validates :region, inclusion: { in: ->(_) { Region.keys } }

  def region_record = Region.find(region) || Region.default

  def initial = email_address.first.upcase

  # The one user of a single-user (self-hosted) install. Created on first use; nobody ever signs in as it.
  LOCAL_EMAIL = "local@propscope.local".freeze

  def self.local
    find_or_create_by!(email_address: LOCAL_EMAIL) do |u|
      u.password = SecureRandom.hex(24)
      u.admin = true
    end
  end
end

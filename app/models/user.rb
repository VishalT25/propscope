class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :saved_filters, dependent: :destroy
  has_many :picks, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :odds_format, inclusion: { in: ->(_) { Rails.configuration.x.odds_formats } }

  def initial = email_address.first.upcase
end

class ApiUsage < ApplicationRecord
  validates :provider, :period, presence: true

  def self.period_for(time = Time.current) = time.utc.strftime("%Y-%m")

  def percent_used = units_limit&.positive? ? (units_used * 100.0 / units_limit) : nil
end

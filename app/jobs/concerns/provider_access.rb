# Jobs are thin: pick a provider, skip when it is live but LIVE_DATA is not set, handle budget errors.
module ProviderAccess
  extend ActiveSupport::Concern

  private

  # Returns the provider, or nil when it would hit a live API without LIVE_DATA=true.
  def provider_for(capability)
    provider = Providers::Registry.for(capability)
    return provider unless provider.live? && !LiveData.enabled?

    Rails.logger.info("[#{self.class.name}] skipped: #{provider.provider_key} is live and LIVE_DATA is not true")
    nil
  end

  def with_budget_handling
    yield
  rescue BudgetGuard::BudgetExceeded => e
    Rails.logger.warn("[#{self.class.name}] #{e.message}")
    nil
  end
end

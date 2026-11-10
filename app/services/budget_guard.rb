# Treats each provider's monthly free-tier limit as a hard ceiling. Plans to use at most `ceiling` (80%).
class BudgetGuard
  class BudgetExceeded < StandardError; end

  class << self
    # Reserve `units` then run the block. Raises BudgetExceeded (without calling) when it would pass 100%.
    def spend!(provider, units, now: Time.current)
      usage = nil
      ApiUsage.transaction do
        usage = usage_for(provider, now).lock!
        limit = usage.units_limit
        if limit && usage.units_used + units > limit
          raise BudgetExceeded, "#{provider} budget exhausted (#{usage.units_used}/#{limit} this month)"
        end

        before = usage.percent_used
        usage.increment!(:units_used, units)
        warn_if_crossed(provider, usage, before)
      end
      yield
    end

    # Optional snapshots (morning/afternoon/T-90) are dropped once usage hits the ceiling.
    def optional_allowed?(provider, now: Time.current)
      usage = usage_for(provider, now)
      pct = usage.percent_used
      pct.nil? || pct < ceiling(provider) * 100
    end

    def usage_for(provider, now = Time.current)
      period = ApiUsage.period_for(now)
      limit = Providers::Registry.budget_config(provider)[:monthly_units]
      ApiUsage.find_or_create_by!(provider: provider.to_s, period: period) { |u| u.units_limit = limit }
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    # How the month is going: units used, and where it lands at the current pace.
    Report = Data.define(:provider, :used, :limit, :percent, :projected, :days_left)

    def report(provider, now: Time.current)
      usage = usage_for(provider, now)
      day = now.utc.day
      days_in_month = now.utc.end_of_month.day
      projected = day.zero? ? usage.units_used : (usage.units_used * days_in_month.to_f / day).round
      Report.new(provider: provider.to_s, used: usage.units_used, limit: usage.units_limit, percent: usage.percent_used, projected: projected, days_left: days_in_month - day)
    end

    private

    def ceiling(provider) = Providers::Registry.budget_config(provider).fetch(:ceiling, 0.8)

    def warn_if_crossed(provider, usage, before)
      threshold = ceiling(provider) * 100
      after = usage.percent_used
      return unless after && after >= threshold && (before.nil? || before < threshold)

      ActiveSupport::Notifications.instrument("budget_warning.propscope", provider: provider, percent: after)
      Rails.logger.warn("[budget] #{provider} reached #{after.round(1)}% of monthly budget; dropping optional snapshots")
    end
  end
end

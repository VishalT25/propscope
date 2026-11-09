# Single place to rename the product.
Rails.application.config.x.app_name = "Propscope"
Rails.application.config.x.odds_formats = %w[american decimal].freeze

# Top N defences are "unfavorable", bottom N "favorable" (capped at a third of the league; see DefenseRanker).
Rails.application.config.x.defense_tier_size = 10

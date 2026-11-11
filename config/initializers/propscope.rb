# Single place to rename the product.
Rails.application.config.x.app_name = "Propscope"
Rails.application.config.x.odds_formats = %w[american decimal].freeze

# Self-hosted copies are single-user by default: no sign-in, one built-in local user holds your picks, saved filters and
# preferences. Set SINGLE_USER=false to turn accounts (sign up / sign in) back on for a shared deployment.
Rails.application.config.x.single_user = ENV.fetch("SINGLE_USER", Rails.env.test? ? "false" : "true") != "false" # specs default to accounts on and cover both modes

# A fresh single-user install opens on the setup page (sample data, or your own keys and a backfill) until that is done.
# REQUIRE_SETUP=false turns the redirect off (for scripted installs); specs run with it off.
Rails.application.config.x.require_setup = ENV.fetch("REQUIRE_SETUP", Rails.env.test? ? "false" : "true") != "false"

# Top N defences are "unfavorable", bottom N "favorable" (capped at a third of the league; see DefenseRanker).
Rails.application.config.x.defense_tier_size = 10

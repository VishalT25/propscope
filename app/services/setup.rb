# Where a fresh install is in getting set up, and the few things that change it. Nothing here calls a provider except Setup.verify.
#
#   data_mode   "sample" (fictional data, no keys) or "live" (the person's own keys; live calls are on)
#   intent      "live" while someone is working through the keys and backfill steps
#
# Stages: choose -> (keys -> backfill ->) done. A populated install from before setup existed counts as sample, so nobody is
# sent through it unasked; the setup page and Settings are always reachable.
module Setup
  CHECK_PREFIX = "key_check.".freeze

  class << self
    def mode
      Setting.get("data_mode") || (ENV["LIVE_DATA"] == "true" ? "live" : (Game.exists? ? "sample" : nil))
    end

    def intent_live? = Setting.get("setup_intent") == "live"

    def live? = mode == "live"

    # Sample data chosen, or live data with its history loaded (or loaded by hand when LIVE_DATA is set in the environment).
    def complete?
      case mode
      when "sample" then true
      when "live" then ENV["LIVE_DATA"] == "true" || BackfillRun.exists?(state: "done")
      else false
      end
    end

    # The first-run page takes over a single-user install until setup is complete (see ApplicationController#require_setup).
    def required? = Rails.configuration.x.require_setup && !complete?

    def stage
      if live? && !complete? then :backfill
      elsif intent_live? then keys_ready? ? :backfill : :keys
      elsif complete? then :done
      else :choose
      end
    end

    # Both keys tested, and the plan includes box scores.
    def keys_ready? = check("sports_game_odds") == "ok" && check("balldontlie") == "box_scores"

    def check(provider) = Setting.get("#{CHECK_PREFIX}#{provider}")

    # Saves a key typed on the setup page. A new key has not been tested yet.
    def save_key(provider, value)
      return if value.blank?

      ApiKeys.set(provider, value)
      Setting.delete("#{CHECK_PREFIX}#{provider}")
    end

    # Tests the key for a provider (see Providers::KeyCheck) and remembers the outcome.
    def verify(provider, checker: Providers::KeyCheck)
      result = checker.call(provider)
      outcome = result.ok ? (result.box_scores == false ? "no_box_scores" : (result.box_scores ? "box_scores" : "ok")) : nil
      Setting.set("#{CHECK_PREFIX}#{provider}", outcome)
      result
    end

    def choose_live = Setting.set("setup_intent", "live")

    # Live data, history loading: the app calls the providers from now on.
    def go_live
      Setting.set("data_mode", "live")
      Setting.set("setup_intent", "live")
    end

    def finish_live = Setting.delete("setup_intent")

    # Sample data: loads it when the database is empty, so there is something to look at.
    def use_sample(seeder: -> { Ingest::SeedFixtures.call })
      Setting.set("data_mode", "sample")
      Setting.delete("setup_intent")
      seeder.call unless Game.exists?
    end
  end
end

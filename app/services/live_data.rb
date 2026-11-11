# Live third-party calls only happen when live data is on: LIVE_DATA=true in the environment, or chosen in setup (Settings).
# A fresh install, and every test, has it off.
module LiveData
  def self.enabled? = ENV["LIVE_DATA"] == "true" || Setting.get("data_mode") == "live"
end

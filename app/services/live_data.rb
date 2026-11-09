# Live third-party calls only happen when LIVE_DATA=true.
module LiveData
  def self.enabled? = ENV["LIVE_DATA"] == "true"
end

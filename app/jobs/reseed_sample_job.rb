# Sample data is a snapshot dated to the day it was loaded, so a day later its slate is in the past and the explorer is empty.
# This re-dates it to today. Only for an install that chose sample data: it never touches live data.
class ReseedSampleJob < ApplicationJob
  queue_as :default

  def perform
    return unless Setting.get("data_mode") == "sample"

    Ingest::SeedFixtures.call
  end
end

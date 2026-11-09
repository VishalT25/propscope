class MarkClosingLinesJob < ApplicationJob
  queue_as :default

  def perform = Ingest::MarkClosingLines.call
end

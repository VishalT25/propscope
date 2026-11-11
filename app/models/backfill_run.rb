class BackfillRun < ApplicationRecord
  STATES = %w[queued running paused failed done cancelled].freeze
  PHASES = { "reference" => "Teams, players and schedule", "box_scores" => "Box scores", "ranks" => "Defence ranks, hit rates and insights", "odds" => "Today's odds" }.freeze
  STALL_AFTER = 10.minutes # a running run that has not reported for this long was interrupted (the server restarted)

  validates :state, inclusion: { in: STATES }
  validates :seasons, inclusion: { in: 1..3 }

  scope :active, -> { where(state: %w[queued running]).where("heartbeat_at IS NULL OR heartbeat_at > ?", STALL_AFTER.ago) }

  def self.latest = order(:id).last

  def active? = state.in?(%w[queued running]) && !stalled?
  def stalled? = state == "running" && heartbeat_at.present? && heartbeat_at < STALL_AFTER.ago
  def done? = state == "done"
  def phase_label = PHASES[phase]
  def percent = total_days.to_i.zero? ? nil : (done_days * 100 / total_days)

  def beat!(**attrs) = update!(heartbeat_at: Time.current, **attrs)
end

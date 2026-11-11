module Backfill
  # Where a load is up to and how long is left, from the run's own progress. Nothing is promised: the pace is what the run has actually
  # managed so far (or a sensible default in its first few requests), so the figure settles as it goes.
  class Eta
    STEPS = %w[reference box_scores ranks odds].freeze
    TITLES = { "reference" => "Teams, players and the schedule", "box_scores" => "Box scores", "ranks" => "Defence ranks, hit rates and insights", "odds" => "Today's odds" }.freeze
    TAIL_SECONDS = 60          # ranks, hit rates, insights and odds after the box scores
    REFERENCE_PACE = 1.7       # seconds per request while the schedule is also being saved
    ENOUGH_REQUESTS = 5        # before this many, use the default pace

    Result = Data.define(:step, :steps, :title, :done, :total, :unit, :step_seconds, :seconds_left, :finish_at, :then_minutes)

    def self.call(run, **) = new(run, **).call

    def initialize(run, now: Time.current, interval: Providers::Registry.min_interval("balldontlie"))
      @run = run
      @now = now
      @interval = interval.to_f
    end

    def call
      step = STEPS.index(@run.phase) || 0
      step_seconds, total, done, unit, then_minutes = send(:"for_#{STEPS[step]}")
      left = step_seconds + (@run.phase == "box_scores" ? TAIL_SECONDS : 0) + (then_minutes.to_i * 60) + (step.zero? ? TAIL_SECONDS : 0)
      Result.new(step + 1, STEPS.size, TITLES.fetch(STEPS[step]), done, total, unit, step_seconds.round, left.round, @now + left, then_minutes)
    end

    private

    # Request count is known roughly (about 7 plus 9 per season); the box-score time is the up-front estimate.
    def for_reference
      expected = Estimate.reference_requests(@run.seasons)
      done = @run.phase_requests
      remaining = [ expected - done, 1 ].max
      [ remaining * pace(default: @interval * REFERENCE_PACE), [ expected, done ].max, done, "requests", Estimate.call(seasons: @run.seasons, interval: @interval).minutes ]
    end

    # Exact: the days are known by now. Each day costs what the days so far have cost.
    def for_box_scores
      done = @run.done_days
      remaining_days = [ @run.total_days - done, 0 ].max
      per_day = done >= 3 ? @run.phase_requests.to_f / done : Estimate::REQUESTS_PER_DAY
      [ remaining_days * per_day * pace(default: @interval * Estimate::OVERHEAD), @run.total_days, done, "game days", 0 ]
    end

    def for_ranks = [ TAIL_SECONDS * 0.7, nil, nil, nil, 0 ]

    def for_odds = [ 15, nil, nil, nil, 0 ]

    # Seconds per request: what this step has managed, once it has made enough of them.
    def pace(default:)
      elapsed = @run.phase_started_at ? @now - @run.phase_started_at : 0
      @run.phase_requests >= ENOUGH_REQUESTS && elapsed.positive? ? elapsed / @run.phase_requests : default
    end
  end
end

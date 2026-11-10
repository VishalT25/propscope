module Games
  # The tiny green/red strips on game cells: how often each side would have cleared TODAY's line in recent games.
  #   moneyline : the team won
  #   spread    : the team covered the current spread (margin + spread > 0)
  #   total     : combined points beat (over) or missed (under) the current total, over both teams' recent games
  class HitStrips
    RECENT = 10
    Strip = Data.define(:outcomes, :rate)

    def self.call(game:, lines:) = new(game, lines).call

    def initialize(game, lines)
      @game, @lines = game, lines
    end

    # => { ["moneyline", "home"] => Strip, ... }
    def call
      strips = {}
      %w[home away].each do |outcome|
        team = outcome == "home" ? @game.home_team_id : @game.away_team_id
        ml = @lines.moneyline[outcome]
        strips[[ "moneyline", outcome ]] = strip(history(team).map { |h| h[:margin].positive? ? true : (h[:margin].zero? ? nil : false) }) if ml
        sp = @lines.spread[outcome]
        strips[[ "spread", outcome ]] = strip(history(team).map { |h| HitRateCalculator.outcome(h[:margin], -sp.line, "over") }) if sp
      end
      %w[over under].each do |side|
        cell = @lines.total[side] or next
        totals = (history(@game.home_team_id).first(RECENT / 2) + history(@game.away_team_id).first(RECENT / 2)).map { |h| h[:total] }
        strips[[ "total", side ]] = strip(totals.map { |t| HitRateCalculator.outcome(t, cell.line, side) })
      end
      strips
    end

    private

    # Newest first; margin is from the team's point of view.
    def history(team_id)
      @history ||= {}
      @history[team_id] ||= Game.final.where("home_team_id = :t OR away_team_id = :t", t: team_id).where(starts_at: ...@game.starts_at)
                                .where.not(home_score: nil).order(starts_at: :desc).limit(RECENT).map do |g|
        mine, theirs = g.home_team_id == team_id ? [ g.home_score, g.away_score ] : [ g.away_score, g.home_score ]
        { margin: mine - theirs, total: mine + theirs }
      end
    end

    def strip(outcomes)
      decided = outcomes.compact
      Strip.new(outcomes: outcomes.reverse, rate: decided.empty? ? nil : BigDecimal(decided.count(true)) * 100 / decided.size)
    end
  end
end

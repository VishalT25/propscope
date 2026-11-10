module Insights
  module Rules
    # A rule turns one prop (market + side) plus its history into zero or more plain-English insights.
    # `call(context) -> [Insights::Result]`. Strength is on one 0-100 scale (see Insights::Strength) so rules rank together.
    class Base
      MIN_SAMPLE = 5

      def self.call(context) = new(context).call

      def initialize(context)
        @c = context
      end

      private

      attr_reader :c

      def name = c.player.full_name
      def stat_label = c.stat.label.downcase
      def line = ActionController::Base.helpers.number_with_precision(c.market.line, precision: 1)
      def over? = c.side == "over"
      def verb = over? ? "gone over" : "stayed under"
      def hit?(game_value) = HitRateCalculator.outcome(game_value.value, c.market.line, c.side)

      def result(statement, rate, n) = Result.new(rule_key: self.class.name.demodulize.underscore, statement: statement, strength: Strength.score(rate, n))

      # Share of decided games (pushes excluded) among `games` that cleared the line on this side.
      def tally(games)
        outs = games.map { |g| hit?(g) }
        hits = outs.count(true)
        decided = hits + outs.count(false)
        [ hits, decided, decided.zero? ? nil : BigDecimal(hits) * 100 / decided ]
      end

      # Consecutive most recent games that cleared the line on this side.
      def streak = c.values.take_while { |g| hit?(g) == true }
    end
  end
end

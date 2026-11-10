module Ingest
  # Resolves quotes onto canonical games/players, then appends snapshots ONLY when price or line changed.
  # Stale quotes (older than the latest snapshot) are ignored, which also settles two providers reporting one book:
  # the more recent quote wins and `source_provider` records where it came from.
  class OddsSnapshots
    Result = Data.define(:inserted, :unchanged, :stale, :unresolved)

    def self.call(**) = new(**).call

    def initialize(quotes:, sport: Sport.nba)
      @quotes, @sport = quotes, sport
      @resolvers = Hash.new { |h, provider| h[provider] = EntityResolver.new(provider: provider, sport: @sport) }
      @games = {}
      @markets = {}
      @books = {}
      @teams = {}
      @players = {}
    end

    def call
      resolved = @quotes.filter_map { |q| (market = market_for(q)) && [ q, market, book_for(q) ] }
      latest = latest_snapshots(resolved.map { |_, m, _| m.id }.uniq)
      counts = { inserted: 0, unchanged: 0, stale: 0 }
      rows = []
      deeplinks = {} # id => link, for unchanged prices whose latest snapshot has no betslip link yet

      resolved.each do |q, market, book|
        key = [ market.id, q.outcome, book.id ]
        last = latest[key]
        if last && q.captured_at <= last[:captured_at] then counts[:stale] += 1
        elsif last && last[:american_odds] == q.american_odds && last[:line] == q.line
          counts[:unchanged] += 1
          deeplinks[last[:id]] = q.deeplink if last[:id] && q.deeplink.present? && last[:deeplink] != q.deeplink
        else
          row = build_row(q, market, book)
          rows << row
          latest[key] = row
          counts[:inserted] += 1
        end
      end

      OddsSnapshot.insert_all(rows) if rows.any?
      deeplinks.each { |id, link| OddsSnapshot.where(id: id).update_all(deeplink: link) } # metadata only: the price did not change
      Result.new(**counts, unresolved: @quotes.size - resolved.size)
    end

    private

    def market_for(q)
      game = @games.fetch([ q.provider, q.event_id ]) do
        @games[[ q.provider, q.event_id ]] = @resolvers[q.provider].game(event_id: q.event_id, home: q.home_team, away: q.away_team, starts_at: q.starts_at)
      end
      return nil unless game

      player = nil
      if q.player
        player = player_for(q)
        return nil unless player
      end

      key = [ game.id, player&.id, q.market_type, q.period, q.line, q.is_alternate ]
      @markets[key] ||= Market.find_or_create_by!(game: game, player: player, market_type: q.market_type, period: q.period,
                                                  line: q.line, is_alternate: q.is_alternate)
    end

    # Memoized per run, including misses, so one unmatched player is recorded once, not once per quote.
    def player_for(q)
      key = [ q.provider, q.player.external_id ]
      return @players[key] if @players.key?(key)

      resolver = @resolvers[q.provider]
      team = @teams.fetch([ q.provider, q.player.team&.external_id ]) { @teams[[ q.provider, q.player.team&.external_id ]] = resolver.team(q.player.team) }
      @players[key] = resolver.player(q.player, team: team)
    end

    def book_for(q) = @books[q.bookmaker_key] ||= Bookmaker.for_key(q.bookmaker_key)

    def latest_snapshots(market_ids)
      OddsSnapshot.where(market_id: market_ids).latest_per_outcome.each_with_object({}) do |s, h|
        h[[ s.market_id, s.outcome, s.bookmaker_id ]] = { id: s.id, american_odds: s.american_odds, line: s.line, captured_at: s.captured_at, deeplink: s.deeplink }
      end
    end

    def build_row(q, market, book)
      { market_id: market.id, bookmaker_id: book.id, outcome: q.outcome, american_odds: q.american_odds,
        decimal_odds: OddsMath.american_to_decimal(q.american_odds), line: q.line, captured_at: q.captured_at,
        source_provider: q.provider, is_closing: false, deeplink: q.deeplink }
    end
  end
end

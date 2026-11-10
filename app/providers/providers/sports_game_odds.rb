module Providers
  # SportsGameOdds: one "event object" carries every market and bookmaker for a game.
  # Free tier: 10 req/min, 2,500 objects/month (1 object per event returned). See docs/providers/sports_game_odds.md.
  class SportsGameOdds < Base
    CAPABILITIES = Set[:odds, :props].freeze
    LEAGUE = { "nba" => "NBA" }.freeze

    # oddID = statID-statEntityID-periodID-betTypeID-sideID  (player props put a playerID in statEntityID)
    STAT_TO_MARKET = {
      "points" => "player_points",
      "rebounds" => "player_rebounds",
      "assists" => "player_assists",
      "threePointersMade" => "player_threes",
      "points+rebounds+assists" => "player_pra"
    }.freeze
    GAME_PERIOD = "game".freeze

    # Alternate lines: each bookmaker entry carries an `altLines` list (up to ~70, many junk such as -10000 or unavailable).
    # Keep the sensible ones: available, a believable price, and a line near the main one.
    ALT_PRICE_RANGE = (-1000..2000)
    ALT_WINDOW = (3.0..10.0) # how far from the main line (35% of it, clamped to this range)

    def provider_key = "sports_game_odds"

    # SGO bills per event returned, regardless of markets or books.
    def cost_of(_kind, count = 1) = count

    def fetch_teams(**) = raise(NotImplementedError)
    def fetch_players(**) = raise(NotImplementedError)
    def fetch_game_logs(**) = raise(NotImplementedError)
    def fetch_events(**) = raise(NotImplementedError, "use fetch_odds: events and odds arrive together")

    def fetch_odds(sport:, event_ids: nil, from: nil, to: nil)
      params = { "leagueID" => LEAGUE.fetch(sport.to_s), "oddsAvailable" => "true" }
      params["includeAltLines"] = "true" if self.class.include_alt_lines? # same cost: billing is per event, not per line
      if event_ids.present?
        params["eventIDs"] = Array(event_ids).join(",")
        units = Array(event_ids).size
      else
        params["startsAfter"] = from.utc.iso8601
        params["startsBefore"] = to.utc.iso8601
        units = Providers::SportsGameOdds.expected_events(from, to)
      end
      body = request("/events", params, cost: [ units, 1 ].max)
      parse_events(body)
    end

    # NBA plays at most ~15 games a day; used only to reserve budget for a window query.
    def self.include_alt_lines? = ENV.fetch("INCLUDE_ALT_LINES", "true") != "false"

    def self.expected_events(from, to) = [ ((to - from) / 1.day * 12).ceil, 1 ].max

    def replay(raw) = [ :odds, parse_events(raw.body) ]

    def parse_events(body)
      fetched_at = clock.call
      body.fetch("data").flat_map { |event| parse_event(event, fetched_at) }
    end

    private

    # One real event is ~1.3MB (1,000+ markets, deep links, colours). Store only what parse_event reads
    # (modeled markets, modeled fields) so 14 days of payloads stay small. replay() parses this slimmed body identically.
    def storage_body(body)
      data = body.fetch("data").map do |event|
        players = event["players"] || {}
        odds = (event["odds"] || {}).filter_map do |odd_id, odd|
          market = classify(odd_id, odd, players) or next
          books = (odd["byBookmaker"] || {}).transform_values do |b|
            kept = b.slice("odds", "overUnder", "spread", "available", "lastUpdatedAt", "deeplink")
            if b["altLines"]
              kept["altLines"] = alt_entries(b, line_for(market, b), market).map { |a| a.slice("odds", "overUnder", "spread", "available", "lastUpdatedAt") }
            end
            kept
          end
          [ odd_id, odd.slice("oddID").merge("byBookmaker" => books) ]
        end.to_h
        event.slice("eventID", "sportID", "leagueID", "type", "status", "players")
             .merge("teams" => slim_teams(event["teams"]), "odds" => odds)
      end
      body.slice("success", "nextCursor", "notice").merge("data" => data)
    end

    def slim_teams(teams)
      (teams || {}).transform_values { |t| t.slice("teamID", "names") }
    end

    def parse_event(event, fetched_at)
      home = team_ref(event.dig("teams", "home"))
      away = team_ref(event.dig("teams", "away"))
      starts_at = parse_time(event.dig("status", "startsAt"))
      players = event["players"] || {}

      (event["odds"] || {}).flat_map do |odd_id, odd|
        market = classify(odd_id, odd, players)
        next [] unless market

        (odd["byBookmaker"] || {}).filter_map do |book_key, entry|
          next if entry["available"] == false

          price = Integer(entry["odds"].to_s, exception: false)
          line = line_for(market, entry)
          next if price.nil? || (market[:market_type] != "moneyline" && line.nil?)

          main = Dto::OddsQuote.new(
            provider: provider_key, event_id: event["eventID"], home_team: home, away_team: away, starts_at: starts_at,
            bookmaker_key: book_key, market_type: market[:market_type], period: GAME_PERIOD, player: market[:player],
            line: line, outcome: market[:outcome], american_odds: price,
            captured_at: parse_time(entry["lastUpdatedAt"]) || fetched_at, is_alternate: false, deeplink: entry["deeplink"].presence
          )
          [ main ] + alt_quotes(main, entry, market, fetched_at)
        end.flatten
      end
    end

    # Returns { market_type:, outcome:, player: } or nil for markets we don't model (periods, team totals, ...).
    def classify(odd_id, odd, players)
      stat, entity, period, bet, side = odd_id.to_s.split("-", 5)
      return nil unless period == GAME_PERIOD && side.present?

      case bet
      when "ml" then { market_type: "moneyline", outcome: side, player: nil } if %w[home away].include?(side) && stat == "points"
      when "sp" then { market_type: "spread", outcome: side, player: nil } if %w[home away].include?(side) && stat == "points"
      when "ou"
        return nil unless %w[over under].include?(side)
        return { market_type: "total", outcome: side, player: nil } if stat == "points" && entity == "all"

        market_type = STAT_TO_MARKET[stat]
        return nil unless market_type && !%w[all home away].include?(entity)

        info = players[entity] || {}
        name = info["name"] || [ info["firstName"], info["lastName"] ].compact.join(" ").presence || entity.titleize
        { market_type: market_type, outcome: side, player: Dto::PlayerRef.new(external_id: entity, name: name, team: player_team(info, odd)) }
      end
    end

    # The sensible alternate lines of one bookmaker entry, as quotes flagged is_alternate.
    def alt_quotes(main, entry, market, fetched_at)
      alt_entries(entry, main.line, market).filter_map do |alt|
        price = Integer(alt["odds"].to_s, exception: false)
        line = line_for(market, alt)
        next if price.nil? || line.nil?

        main.with(line: line, american_odds: price, captured_at: parse_time(alt["lastUpdatedAt"]) || fetched_at, is_alternate: true, deeplink: nil)
      end
    end

    # Raw altLines worth keeping: available, a believable price, a different line than the main one, and near it.
    def alt_entries(entry, main_line, market)
      return [] if main_line.nil? || market[:market_type] == "moneyline"

      window = (main_line.abs * 0.35).to_f.clamp(ALT_WINDOW.begin, ALT_WINDOW.end)
      Array(entry["altLines"]).select do |alt|
        price = Integer(alt["odds"].to_s, exception: false)
        line = line_for(market, alt)
        alt["available"] != false && price && ALT_PRICE_RANGE.cover?(price) && line && line != main_line && (line - main_line).abs <= window
      end
    end

    def player_team(info, _odd)
      info["teamID"] ? Dto::TeamRef.new(external_id: info["teamID"], name: nil, abbreviation: nil) : nil
    end

    def line_for(market, entry)
      raw = market[:market_type] == "spread" ? (entry["spread"] || entry["overUnder"]) : entry["overUnder"]
      raw.present? ? BigDecimal(raw.to_s) : nil
    rescue ArgumentError
      nil
    end

    def team_ref(team)
      return nil unless team

      names = team["names"] || {}
      Dto::TeamRef.new(external_id: team["teamID"], name: names["long"] || names["medium"], abbreviation: names["short"])
    end
  end
end

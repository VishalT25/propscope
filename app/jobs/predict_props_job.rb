# Asks the optional model service for a projection and over/under probability for each upcoming points prop.
# Never raises when the service is missing or down: the app simply has no Model column until it is back.
class PredictPropsJob < ApplicationJob
  queue_as :default

  STAT = StatCatalog.for_market("player_points")

  def perform(client: ModelClient.new)
    return unless client.enabled?
    return if client.open? # circuit breaker: do not even build features for a service that is known to be down

    markets = Market.joins(:game).where(games: { starts_at: Time.current.. }, market_type: STAT.market_type, is_alternate: false)
                    .where.not(player_id: nil).includes(:game, player: :team).to_a
    rows = build_rows(markets)
    return if rows.empty?

    result = client.predict(rows.values.map { |r| r.slice(:id, :line, :features) })
    save(result, rows)
  rescue ModelClient::Unavailable => e
    Rails.logger.warn("[PredictPropsJob] skipped: #{e.message}")
  end

  private

  def build_rows(markets)
    builder = ModelFeatures.new(stat: STAT)
    markets.each_with_object({}) do |m, rows|
      team = m.player.team_id
      next unless team && [ m.game.home_team_id, m.game.away_team_id ].include?(team)

      home = m.game.home_team_id == team
      features = builder.features_for(player_id: m.player_id, team_id: team, opponent_id: home ? m.game.away_team_id : m.game.home_team_id,
                                      date: m.game.slate_date, season: m.game.season, home: home)
      rows[m.id.to_s] = { id: m.id.to_s, line: m.line.to_f, features: features, market: m } if features
    end
  end

  def save(result, rows)
    now = Time.current
    records = result[:predictions].filter_map do |p|
      market = rows.dig(p["id"], :market) or next
      %w[over under].map do |side|
        probability = BigDecimal(p["p_#{side}"].to_s).clamp(BigDecimal("0.0001"), BigDecimal("0.9999"))
        { market_id: market.id, side: side, probability: probability, projection: p["projection"], model_version: result[:model_version], computed_at: now, created_at: now, updated_at: now }
      end
    end.flatten
    Prediction.upsert_all(records, unique_by: %i[market_id side]) if records.any?
  end
end

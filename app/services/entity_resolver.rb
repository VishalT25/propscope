# Matches provider entities onto canonical records (BallDontLie is canonical).
# Order: exact external ID, then heuristics. Anything unresolved is recorded and SKIPPED, never guessed.
class EntityResolver
  GAME_WINDOW = 3.hours

  def initialize(provider:, sport:)
    @provider = provider.to_s
    @sport = sport
  end

  def team(ref)
    return nil unless ref

    found = ExternalId.lookup(@provider, "team", ref.external_id)
    found ||= match_team(ref)
    return register(found, "team", ref.external_id) if found

    unresolved("team", ref.external_id, ref.to_h, "no team matches abbreviation or name")
  end

  def player(ref, team: nil)
    return nil unless ref

    found = ExternalId.lookup(@provider, "player", ref.external_id)
    found ||= match_player(ref, team)
    return register(found, "player", ref.external_id) if found

    unresolved("player", ref.external_id, ref.to_h, "no player matches normalized name and team")
  end

  def game(event_id:, home:, away:, starts_at:)
    found = ExternalId.lookup(@provider, "game", event_id)
    return found if found

    home_team = team(home)
    away_team = team(away)
    if home_team && away_team && starts_at
      found = @sport.games.where(home_team: home_team, away_team: away_team)
                    .where(starts_at: (starts_at - GAME_WINDOW)..(starts_at + GAME_WINDOW)).first
    end
    return register(found, "game", event_id) if found

    unresolved("game", event_id, { home: home.to_h, away: away.to_h, starts_at: starts_at }, "no game with these teams near start time")
  end

  private

  def match_team(ref)
    teams = @sport.teams
    found = teams.find_by("lower(abbreviation) = ?", ref.abbreviation.to_s.downcase) if ref.abbreviation.present?
    found || (ref.name.present? && teams.detect { |t| NameNormalizer.call(t.name) == NameNormalizer.call(ref.name) })
  end

  def match_player(ref, team)
    return nil unless team

    candidates = @sport.players.where(normalized_name: NameNormalizer.call(ref.name), team_id: team.id)
    candidates.one? ? candidates.first : nil
  end

  def register(record, type, external_id)
    ExternalId.register!(@provider, type, external_id, record)
    UnresolvedEntity.where(provider: @provider, external_type: type, external_id: external_id.to_s, resolved_at: nil).find_each(&:resolve!)
    record
  end

  def unresolved(type, external_id, payload, reason)
    UnresolvedEntity.record!(provider: @provider, type: type, external_id: external_id, payload: payload, reason: reason)
    nil
  end
end

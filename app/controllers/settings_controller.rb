# Settings and About: images for one league's teams and players, and what version of the app this is.
class SettingsController < ApplicationController
  PLAYER_RESULTS = 12

  helper_method :can_edit_images?

  def show
    @build = BuildInfo.call
    @league = current_league
    @sport = Sport.find_by(key: @league.key)
    @teams = Team.where(sport: @sport).order(:name).to_a
    @query = params[:q].to_s.strip.first(60)
    @players = player_rows
    @coverage = coverage
    @last_odds_at = OddsSnapshot.maximum(:captured_at)
  end

  private

  def can_edit_images? = current_user&.admin?

  # A search for someone, or (with no search) the players who already have a photo so they can be changed or removed.
  def player_rows
    scope = Player.where(sport: @sport).includes(:team).order(:last_name, :first_name).limit(PLAYER_RESULTS)
    return scope.where.not(photo_url: nil).to_a if @query.blank?

    scope.where("normalized_name LIKE ?", "%#{Player.sanitize_sql_like(NameNormalizer.call(@query))}%").to_a
  end

  # How many of this league's teams and players already have an image.
  def coverage
    { teams: [ Team.where(sport: @sport).where.not(logo_url: nil).count, Team.where(sport: @sport).count ],
      players: [ Player.where(sport: @sport).where.not(photo_url: nil).count, Player.where(sport: @sport).count ] }
  end
end

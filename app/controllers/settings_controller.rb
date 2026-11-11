# Settings and About: images for teams and players, and what version of the app this is.
class SettingsController < ApplicationController
  PLAYER_RESULTS = 12

  helper_method :can_edit_images?

  def show
    @build = BuildInfo.call
    @teams = Team.includes(:sport).order(:name).to_a
    @query = params[:q].to_s.strip.first(60)
    @players = player_rows
    @last_odds_at = OddsSnapshot.maximum(:captured_at)
  end

  private

  def can_edit_images? = current_user&.admin?

  # A search for someone, or (with no search) the players who already have a photo so they can be changed or removed.
  def player_rows
    scope = Player.includes(:team).order(:last_name, :first_name).limit(PLAYER_RESULTS)
    return scope.where.not(photo_url: nil).to_a if @query.blank?

    scope.where("normalized_name LIKE ?", "%#{Player.sanitize_sql_like(NameNormalizer.call(@query))}%").to_a
  end
end

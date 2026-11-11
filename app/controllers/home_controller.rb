# The landing page: every saved slip, newest first, in play before settled.
class HomeController < PublicController
  def show
    slips = current_user ? current_user.slips.includes(:bookmaker, legs: [ :bookmaker, { market: [ { game: %i[home_team away_team] }, { player: :team } ] } ]).order(created_at: :desc).to_a : []
    @settlements = slips.index_with { |s| Slips::Settlement.call(s) }
    @in_play, @settled = slips.partition { |s| @settlements[s].status == :pending }
  end
end

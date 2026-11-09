module Dto
  GameLog = Data.define(
    :provider, :game_external_id, :player_external_id, :player_name, :team_external_id,
    :opponent_team_external_id, :game_date, :home, :minutes, :points, :rebounds, :assists,
    :threes_made, :steals, :blocks, :turnovers, :fouls, :stats
  )
end

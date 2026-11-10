"""The feature contract shared with Rails. Rails computes these from our database (single source of truth for the
logic); this service only evaluates the model. Every name is about the player's PRIOR games, never the game being predicted.
"""

FEATURES = [
    "mean_l5", "mean_l10", "mean_l20", "mean_season", "std_l10",   # the target stat
    "min_l5", "min_l10",                                           # minutes played
    "fga_l10", "fg3a_l10", "fta_l10",                              # shot volume
    "is_home", "rest_days", "back_to_back",
    "team_scored_l10", "opp_scored_l10", "opp_allowed_l10",        # team scoring environment
    "games_played",                                                # sample size (prior games this season)
]

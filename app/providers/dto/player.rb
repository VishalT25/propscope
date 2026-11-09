module Dto
  Player = Data.define(:provider, :external_id, :first_name, :last_name, :position, :team)  # team: TeamRef or nil
end

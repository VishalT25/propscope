module Dto
  # A team as named by an odds/stats provider (enough to resolve it to a canonical Team).
  TeamRef = Data.define(:external_id, :name, :abbreviation)
end

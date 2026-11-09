# Seeding the fixture slate takes a few seconds. Do it once per example group instead of once per example,
# then truncate (the rows are committed, so transactional rollback cannot remove them).
module SeededData
  def seed_fixtures_once
    before(:context) { Ingest::SeedFixtures.call }
    after(:context) do
      conn = ActiveRecord::Base.connection
      conn.truncate_tables(*(conn.tables - %w[schema_migrations ar_internal_metadata]))
    end
  end
end

RSpec.configure { |c| c.extend SeededData }

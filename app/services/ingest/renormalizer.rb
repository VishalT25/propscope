module Ingest
  # Re-parses stored raw payloads (no API calls, no budget) after a parser fix.
  class Renormalizer
    def self.call(provider:, since:)
      count = 0
      RawPayload.where(provider: provider).where(fetched_at: since..).order(:fetched_at).find_each do |raw|
        kind, records = Providers::Registry.parser(provider, at: raw.fetched_at).replay(raw)
        dispatch(kind, records)
        count += 1
      end
      count
    end

    def self.dispatch(kind, records)
      case kind
      when :teams then ReferenceData.call(teams: records)
      when :players then ReferenceData.call(players: records)
      when :events then ReferenceData.call(events: records)
      when :game_logs then GameLogs.call(logs: records)
      when :odds then OddsSnapshots.call(quotes: records)
      end
    end
  end
end

module Providers
  # Serves recorded vendor JSON from spec/fixtures/providers/<provider>/. Same parsing path as live,
  # no network, no budget. Dates are shifted so the sample slate is always "today".
  class FixtureTransport
    ANCHOR = Date.new(2026, 11, 9) # the date the fixtures were generated for
    ROOT = Rails.root.join("spec/fixtures/providers")
    DATE_RE = /\d{4}-\d{2}-\d{2}/

    def initialize(provider, today: Date.current)
      @provider = provider
      @delta = (today - ANCHOR).to_i
    end

    def metered? = false

    def get(path, params = {})
      file = ROOT.join(@provider, "#{path.delete_prefix('/').tr('/', '_')}.json")
      raise ArgumentError, "no fixture for #{path} (#{file})" unless file.exist?

      body = JSON.parse(shift_dates(file.read))
      filter(path, body, params)
    end

    private

    def shift_dates(text)
      return text if @delta.zero?

      text.gsub(DATE_RE) { |d| (Date.iso8601(d) + @delta).iso8601 }
    end

    # Mimic the date filters the real APIs apply, so adapters exercise the same code path.
    def filter(path, body, params)
      case path
      when "/games"
        from, to = params["start_date"], params["end_date"]
        body["data"] = body["data"].select { |g| (from.nil? || g["date"] >= from) && (to.nil? || g["date"] <= to) }
        body
      when "/stats"
        dates = Array(params["dates[]"] || params["dates"])
        body["data"] = body["data"].select { |s| dates.empty? || dates.include?(s.dig("game", "date")) }
        body
      else
        body
      end
    end
  end
end

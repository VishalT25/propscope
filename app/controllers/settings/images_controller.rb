module Settings
  # Bulk upload for one league: many team logos or many player photos at once, matched by file name. The page sends the files in
  # small batches (a request is limited to 128 files) and shows every file's result from the JSON this returns.
  class ImagesController < BaseController
    MAX_FILES_PER_REQUEST = 50
    KINDS = %w[teams players].freeze

    before_action :load_league_and_kind

    def create
      files = Array(params[:files]).select { |f| f.respond_to?(:tempfile) }.first(MAX_FILES_PER_REQUEST)
      return render(json: { error: "No files were received." }, status: :unprocessable_content) if files.empty?

      results = Images::Bulk.call(sport: @sport, kind: @kind, files: files)
      render json: { results: results.map { |r| { file: r.file, status: r.status, target: r.target, message: r.message } }, totals: totals }
    end

    # The list of exact file names, as a CSV download.
    def names
      send_data Images::ExpectedNames.to_csv(Images::ExpectedNames.call(sport: @sport, kind: @kind)),
                filename: "#{@league.key}-#{@kind}-file-names.csv", type: "text/csv"
    end

    private

    def load_league_and_kind
      @league = League.find(params[:league])
      @kind = params[:kind].to_s
      return render(json: { error: "Unknown league or kind." }, status: :unprocessable_content) unless @league&.enabled? && KINDS.include?(@kind)

      @sport = Sport.find_by(key: @league.key)
      render(json: { error: "No data for #{@league.name} yet." }, status: :unprocessable_content) unless @sport
    end

    def totals
      scope, field = @kind == "teams" ? [ Team.where(sport: @sport), :logo_url ] : [ Player.where(sport: @sport), :photo_url ]
      { with_image: scope.where.not(field => nil).count, total: scope.count }
    end
  end
end

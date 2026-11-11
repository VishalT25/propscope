module Settings
  class LogosController < BaseController
    def update
      team = Team.find(params[:id])
      Images::Attach.call(record: team, file: params[:image])
      back_to_settings notice: "#{team.name} logo updated."
    rescue Images::Attach::Invalid => e
      back_to_settings alert: e.message
    end

    def destroy
      team = Images::Remove.call(record: Team.find(params[:id]))
      back_to_settings notice: "#{team.name} logo removed."
    end
  end
end

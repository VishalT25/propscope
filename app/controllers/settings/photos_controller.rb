module Settings
  class PhotosController < BaseController
    def update
      player = Player.find(params[:id])
      Images::Attach.call(record: player, file: params[:image])
      back_to_settings notice: "#{player.full_name} photo updated."
    rescue Images::Attach::Invalid => e
      back_to_settings alert: e.message
    end

    def destroy
      player = Images::Remove.call(record: Player.find(params[:id]))
      back_to_settings notice: "#{player.full_name} photo removed."
    end
  end
end

module Settings
  # Changing a logo or photo changes it for everyone who uses this install, so it takes an admin
  # (in single-user mode the one local user is an admin).
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      return if current_user&.admin?
      return render(json: { error: "Only an admin can change images." }, status: :forbidden) if request.format.json? || request.xhr?

      redirect_to settings_path, alert: "Only an admin can change images.", status: :see_other
    end

    def back_to_settings(**flash) = redirect_to(settings_path(league: params[:league].presence, q: params[:q].presence, anchor: params[:section]), status: :see_other, **flash)
  end
end

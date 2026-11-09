class ApplicationController < ActionController::Base
  include Authentication
  include OddsFormatPreference
  include BookSelection

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Always know who is signed in (guests are allowed on public pages).
  before_action :resume_session

  helper_method :current_user, :current_league

  private
    def current_user = Current.user

    def current_league
      @current_league ||= League.find(params[:league]) || League.default
    end
end

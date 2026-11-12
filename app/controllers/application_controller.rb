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
  before_action :use_local_user
  before_action :require_setup
  before_action { Setup.refresh_sample_if_stale if request.get? && request.format.html? }

  helper_method :single_user?, :slip

  helper_method :current_user, :current_league, :current_region

  private

  def single_user? = Rails.configuration.x.single_user

  def use_local_user
    Current.local_user = User.local if single_user? && Current.session.nil?
  end

  # A fresh single-user install opens on the setup page until it has sample data or your own data (see Setup).
  def require_setup
    redirect_to setup_path if single_user? && Setup.required?
  end

  # In single-user mode nothing needs a login.
  def require_authentication
    resume_session || single_user? || request_authentication
  end

  # The My Picks slip for whoever is using the app, with their chosen book and stake.
  def slip
    @slip ||= current_user && PickSlip.call(user: current_user, book_key: cookies[:slip_book].presence, stake: cookies[:slip_stake])
  end
    def current_user = Current.user

    # Where this person bets (sportsbook links depend on it). Guests have no slip, so the default is only ever shown, never used.
    def current_region = current_user&.region_record || Region.default

    def current_league
      @current_league ||= League.find(params[:league]) || League.default
    end
end

class RegistrationsController < PublicController
  before_action :accounts_are_off, if: :single_user?
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[email_address password password_confirmation]))
    @user.odds_format = odds_format
    if @user.save
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Welcome to #{Rails.configuration.x.app_name}!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def accounts_are_off = redirect_to(root_path, notice: "Accounts are off: this copy is single-user, so there is nothing to sign in to.")
end

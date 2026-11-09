class RegistrationsController < PublicController
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
end

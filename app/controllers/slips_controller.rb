# Saved slips. Saving snapshots the working slip (see Slips::Save); the working slip stays as it is.
class SlipsController < ApplicationController
  def create
    saved = Slips::Save.call(user: current_user, slip: slip, name: params[:name])
    respond(notice: "Saved “#{saved.name}”. Find it on Home.")
  rescue Slips::Save::Unpriced => e
    respond(alert: e.message)
  end

  def destroy
    current_user.slips.find(params[:id]).destroy
    redirect_to root_path, notice: "Slip deleted.", status: :see_other
  end

  private

  def respond(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("toast", partial: "shared/toast", locals: { message: notice || alert, kind: alert ? :error : :ok }) }
      format.html { redirect_back_or_to root_path, notice: notice, alert: alert, status: :see_other }
    end
  end
end

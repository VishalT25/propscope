# First run, and "change my keys / load more history" later: pick sample data or your own, save and test the keys, then load history
# in the background with progress. Only an admin (in single-user mode, the one local user) can change how the app gets its data.
class SetupsController < ApplicationController
  skip_before_action :require_setup
  before_action :require_admin

  def show
    # Looking never changes anything: ?step= only picks which page to show.
    @stage = case params[:step]
    when "choose" then :choose
    when "keys" then :keys
    when "backfill" then Setup.keys_ready? ? :backfill : :keys
    else Setup.stage
    end
    @run = BackfillRun.latest
    @estimates = [ 1, 2 ].index_with { |seasons| Backfill::Estimate.call(seasons: seasons) }
  end

  def choose
    case params[:mode]
    when "sample"
      Setup.use_sample
      redirect_to root_path, notice: "Sample data loaded. It is made up, so use it to look around. Switch to your own data any time in Settings."
    when "live"
      Setup.choose_live
      redirect_to setup_path
    else
      Setting.delete("setup_intent")
      redirect_to setup_path
    end
  end

  # Saves any keys typed (a blank box keeps what is there) and tests every key that is present.
  def keys
    ApiKeys::PROVIDERS.each_key { |provider| Setup.save_key(provider, params.dig(:keys, provider)) }
    results = ApiKeys::PROVIDERS.keys.filter_map { |provider| [ provider, Setup.verify(provider) ] if ApiKeys.present?(provider) }
    problems = results.reject { |_, r| r.ok && r.box_scores != false }.map { |provider, r| "#{ApiKeys.name(provider)}: #{r.message}" }
    missing = ApiKeys::PROVIDERS.keys.reject { |p| ApiKeys.present?(p) }.map { |p| "Add your #{ApiKeys.name(p)} key." }
    if problems.any? || missing.any?
      redirect_to setup_path(step: "keys"), alert: (problems + missing).join(" ")
    else
      Setup.choose_live
      redirect_to setup_path, notice: "Both keys work. Now load your history."
    end
  end

  def backfill
    return redirect_to(setup_path(step: "keys"), alert: "Test your keys first.") unless Setup.keys_ready?

    Setup.go_live
    Backfill::Start.call(seasons: params[:seasons].to_i.clamp(1, 3))
    redirect_to setup_path
  end

  def cancel
    run = BackfillRun.latest
    run.update!(cancel_requested: true) if run&.active?
    redirect_to setup_path
  end

  def refresh_odds
    if LiveData.enabled?
      SnapshotOddsJob.perform_later("morning")
      redirect_back_or_to settings_path, notice: "Fetching odds now. It takes a few seconds; reload to see them."
    else
      redirect_back_or_to settings_path, alert: "Live data is off, so there is nothing to fetch."
    end
  end

  # The progress panel, reloaded every few seconds while a run is going.
  def progress
    render partial: "setups/progress_frame", locals: { run: BackfillRun.latest }
  end

  private

  def require_admin
    redirect_to root_path, alert: "Only an admin can change how the app gets its data." unless current_user&.admin?
  end
end

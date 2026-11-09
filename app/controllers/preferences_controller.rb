class PreferencesController < PublicController
  def update
    fmt = params[:odds_format].to_s
    if Rails.configuration.x.odds_formats.include?(fmt)
      cookies.permanent[:odds_format] = { value: fmt, same_site: :lax }
      Current.user&.update!(odds_format: fmt)
    end
    redirect_back_or_to root_path, status: :see_other
  end
end

# American odds by default. Stored on the user when signed in, otherwise in a cookie.
module OddsFormatPreference
  extend ActiveSupport::Concern

  included { helper_method :odds_format }

  private
    def odds_format
      fmt = Current.user&.odds_format.presence || cookies[:odds_format].presence
      Rails.configuration.x.odds_formats.include?(fmt) ? fmt : "american"
    end
end

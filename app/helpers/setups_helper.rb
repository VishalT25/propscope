module SetupsHelper
  # "about 11 minutes", "less than a minute": a rough, honest way to say a number of seconds.
  def eta_phrase(seconds)
    s = seconds.to_i
    return "less than a minute" if s < 45
    return "about a minute" if s < 90
    return "about #{(s / 60.0).round} minutes" if s < 3600

    hours, minutes = (s / 60.0).round.divmod(60)
    minutes.zero? ? "about #{pluralize(hours, 'hour')}" : "about #{pluralize(hours, 'hour')} #{minutes} min"
  end
end

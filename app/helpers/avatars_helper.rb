# Our own icons: monogram badges tinted from a hash of the code. No third-party logos or photos.
# If a record has a logo_url / photo_url (licensed images supplied by the self-hoster) we show that instead.
module AvatarsHelper
  SIZES = { dot: "size-4", xs: "size-5", sm: "size-7 text-2xs", md: "size-9 text-xs", lg: "size-14 text-lg", xl: "size-20 text-2xl" }.freeze

  # Stable hue from any string (crc32 is deterministic across processes, unlike String#hash).
  # Kept to 10..215 degrees (red, orange, gold, green, teal, cyan): the indigo and violet band is deliberately excluded.
  def hue_for(key) = 10 + (Zlib.crc32(key.to_s) % 205)

  def tint_style(key)
    "background: oklch(46% 0.1 #{hue_for(key)}); color: oklch(97% 0.012 #{hue_for(key)})"
  end

  def team_badge(team, size: :sm)
    return tag.span("?", class: "#{badge_base} #{SIZES.fetch(size)} bg-surface-2 text-muted") unless team

    if team.logo_url.present?
      image_tag(team.logo_url, alt: team.name, class: "#{SIZES.fetch(size).split.first} shrink-0 object-contain", loading: "lazy")
    else
      # The xs and dot badges are colour markers only: every use sits beside the abbreviation as text, and 11px letters do not fit in 20px.
      tag.span(%i[dot xs].include?(size) ? nil : team.abbreviation.first(3), class: "#{badge_base} #{SIZES.fetch(size)}", style: tint_style(team.abbreviation), title: team.name, role: "img", "aria-label": team.name)
    end
  end

  # Player avatar: photo if supplied, else initials on the team's tint, with a small team badge in the corner.
  def player_avatar(player, size: :md, badge: true)
    inner = if player.photo_url.present?
      image_tag(player.photo_url, alt: player.full_name, class: "#{SIZES.fetch(size).split.first} shrink-0 rounded-full object-cover", loading: "lazy")
    else
      initials = [ player.first_name, player.last_name ].map { |n| n.to_s.scan(/\p{Alpha}/).first }.join.upcase
      tag.span(initials, class: "#{badge_base} #{SIZES.fetch(size)}", style: tint_style(player.team&.abbreviation || player.last_name), title: player.full_name, role: "img", "aria-label": player.full_name)
    end
    return inner unless badge && player.team

    tag.span(class: "relative inline-block shrink-0") do
      safe_join([ inner, tag.span(team_badge(player.team, size: :dot), class: "absolute -bottom-1.5 -right-1.5 rounded-full ring-2 ring-surface") ])
    end
  end

  # Hero background: a wash of the player's team tint into the opponent's, over the dark canvas.
  def hero_style(team, opponent)
    "background: linear-gradient(115deg, oklch(30% 0.06 #{hue_for(team&.abbreviation)}) 0%, var(--color-base-200) 52%, oklch(29% 0.055 #{hue_for(opponent&.abbreviation)}) 100%)"
  end

  def book_badge(bookmaker, size: :sm)
    if bookmaker.logo_url.present?
      image_tag(bookmaker.logo_url, alt: bookmaker.name, class: "#{SIZES.fetch(size).split.first} shrink-0 rounded-md object-contain", loading: "lazy")
    else
      tag.span(bookmaker.code, class: "inline-grid h-7 min-w-9 shrink-0 place-items-center rounded-md px-1 text-2xs font-extrabold tracking-wide",
                               style: tint_style(bookmaker.key), title: bookmaker.name)
    end
  end

  private

  def badge_base = "inline-grid shrink-0 place-items-center rounded-full font-extrabold leading-none"
end

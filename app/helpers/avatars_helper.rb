# Our own icons: monogram badges tinted from a hash of the code. No third-party logos or photos.
# If a record has a logo_url / photo_url (licensed images supplied by the self-hoster) we show that instead.
module AvatarsHelper
  SIZES = { xs: "size-5 text-[8px]", sm: "size-7 text-[10px]", md: "size-9 text-xs", lg: "size-14 text-lg", xl: "size-20 text-2xl" }.freeze

  # Stable hue 0..359 from any string (crc32 is deterministic across processes, unlike String#hash).
  def hue_for(key) = Zlib.crc32(key.to_s) % 360

  def tint_style(key)
    hue = hue_for(key)
    "background: linear-gradient(135deg, hsl(#{hue} 62% 46%), hsl(#{(hue + 28) % 360} 58% 34%)); color: #fff"
  end

  def team_badge(team, size: :sm)
    return tag.span("?", class: "#{badge_base} #{SIZES.fetch(size)} bg-surface-2 text-muted") unless team

    if team.logo_url.present?
      image_tag(team.logo_url, alt: team.name, class: "#{SIZES.fetch(size).split.first} shrink-0 object-contain", loading: "lazy")
    else
      tag.span(team.abbreviation.first(3), class: "#{badge_base} #{SIZES.fetch(size)}", style: tint_style(team.abbreviation), title: team.name, role: "img", "aria-label": team.name)
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
      safe_join([ inner, tag.span(team_badge(player.team, size: :xs), class: "absolute -bottom-1 -right-1 rounded-full ring-2 ring-surface") ])
    end
  end

  def book_badge(bookmaker, size: :sm)
    if bookmaker.logo_url.present?
      image_tag(bookmaker.logo_url, alt: bookmaker.name, class: "#{SIZES.fetch(size).split.first} shrink-0 rounded-md object-contain", loading: "lazy")
    else
      tag.span(bookmaker.code, class: "inline-grid h-7 min-w-9 shrink-0 place-items-center rounded-md px-1 text-[10px] font-extrabold tracking-wide",
                               style: tint_style(bookmaker.key), title: bookmaker.name)
    end
  end

  private

  def badge_base = "inline-grid shrink-0 place-items-center rounded-full font-extrabold leading-none"
end

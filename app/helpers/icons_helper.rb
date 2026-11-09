module IconsHelper
  ICONS = {
    menu: "M4 6h16M4 12h16M4 18h16",
    close: "M6 6l12 12M18 6L6 18",
    ticket: "M3 9V7a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v2a3 3 0 0 0 0 6v2a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-2a3 3 0 0 0 0-6z",
    chevron: "M6 9l6 6 6-6",
    check: "M5 12l5 5L20 7",
    bars: "M6 20V10M12 20V4M18 20v-7",
    sun: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5",
    moon: "M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z",
    user: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 20a8 8 0 0 1 16 0",
    arrow_up: "M12 19V5M6 11l6-6 6 6"
  }.freeze

  def icon(name, css: "size-5")
    tag.svg(tag.path(d: ICONS.fetch(name.to_sym)), class: css, viewBox: "0 0 24 24", fill: "none",
            stroke: "currentColor", "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": true)
  end
end

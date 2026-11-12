# A QR code as inline SVG (rqrcode draws it; no image libraries). QR readers want near-black on near-white whatever the theme, so the
# colours here are fixed, and the .qr-card class gives it its light background.
module QrHelper
  QR_DARK = "#0d1a1d".freeze

  def qr_svg(text, label:)
    svg = RQRCode::QRCode.new(text.to_s, level: :m).as_svg(color: QR_DARK, shape_rendering: "crispEdges", module_size: 4, standalone: true, use_path: true,
                                                          viewbox: true, svg_attributes: { role: "img", "aria-label": label, class: "size-full" })
    svg.html_safe # drawn by rqrcode from our own link text, never from markup
  end
end

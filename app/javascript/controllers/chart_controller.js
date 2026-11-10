import { Controller } from "@hotwired/stimulus"
import "chart.umd" // vendored Chart.js UMD build: a single file that registers window.Chart (no module chunks to resolve)

const { Chart } = window // UMD build registers every controller, element and scale itself

// Renders a chart from a server-built config. Colours are named design tokens ("hit", "miss", ...) resolved
// from CSS variables, so charts follow the dark/light theme.
//   config: { type, labels, decimals, datasets: [{ kind, label, data, colors|color, dash, step, hidden, group }] }
export default class extends Controller {
  static targets = ["canvas"]
  static values = { config: Object }

  connect() {
    this.build()
    this.observer = new MutationObserver(() => this.build())
    this.observer.observe(document.documentElement, { attributes: true, attributeFilter: [ "data-theme" ] })
  }

  disconnect() { this.observer?.disconnect(); this.chart?.destroy() }

  // Checkbox: overlay every game's closing line.
  toggleClosing(event) { this.#setHidden((d) => d.kind === "closing", !event.target.checked) }

  // Buttons: show one of several exclusive reference lines (e.g. average vs median).
  show(event) {
    const group = event.params.group
    this.#setHidden((d) => d.group !== undefined, false, (d) => d.group !== group)
    this.element.querySelectorAll("[data-chart-group-param]").forEach((b) => b.setAttribute("aria-pressed", b.dataset.chartGroupParam === group))
  }

  build() {
    this.chart?.destroy()
    const cfg = this.configValue
    const css = getComputedStyle(document.documentElement)
    const color = (name) => css.getPropertyValue(`--${name}`).trim() || name
    const muted = color("muted")
    const decimals = cfg.decimals ?? 0

    const datasets = cfg.datasets.map((d) => {
      const base = { label: d.label, data: d.data, hidden: !!d.hidden, _meta: d }
      if (d.kind === "bars") return { ...base, type: "bar", backgroundColor: d.colors.map(color), borderRadius: 4, maxBarThickness: 36, order: 2 }
      return { ...base, type: "line", borderColor: color(d.color), backgroundColor: color(d.color), borderDash: d.dash ? [ 6, 5 ] : [], borderWidth: d.kind === "movement" ? 2.5 : 2,
               pointRadius: d.kind === "line" || d.group ? 0 : (d.kind === "closing" ? 5 : 3), pointStyle: d.kind === "closing" ? "rectRounded" : "circle", stepped: d.step ? "before" : false, fill: false, order: 1, spanGaps: true }
    })

    const valueLabels = {
      id: "valueLabels",
      afterDatasetsDraw: (chart) => {
        const { ctx } = chart
        chart.data.datasets.forEach((ds, i) => {
          if (ds._meta.kind !== "bars" || chart.getDatasetMeta(i).hidden) return
          ctx.save(); ctx.fillStyle = color("fg"); ctx.font = "600 11px Inter, system-ui, sans-serif"; ctx.textAlign = "center"
          chart.getDatasetMeta(i).data.forEach((bar, j) => { const v = ds.data[j]; if (v !== null && v !== undefined) ctx.fillText(Number(v).toFixed(decimals), bar.x, bar.y - 5) })
          ctx.restore()
        })
      }
    }

    this.chart = new Chart(this.canvasTarget, {
      data: { labels: cfg.labels, datasets },
      options: {
        responsive: true, maintainAspectRatio: false, animation: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? false : { duration: 500, easing: "easeOutQuart" }, layout: { padding: { top: 18 } },
        plugins: { legend: { display: datasets.length > 1, labels: { color: muted, usePointStyle: true, boxWidth: 8, filter: (item, data) => { const ds = data.datasets[item.datasetIndex]; return !ds.hidden && !(ds._meta.kind === "bars" && new Set(ds._meta.colors).size > 1) } } },
                   tooltip: { callbacks: { label: (c) => `${c.dataset.label}: ${Number(c.parsed.y).toFixed(decimals || (c.dataset._meta.kind === "line" ? 1 : 0))}` } } },
        scales: { x: { ticks: { color: muted, maxRotation: 60, autoSkip: true }, grid: { display: false } },
                  y: { beginAtZero: cfg.beginAtZero !== false, ticks: { color: muted }, grid: { color: color("line") }, grace: "8%" } }
      },
      plugins: [ valueLabels ]
    })
  }

  #setHidden(matches, hidden, hiddenFn) {
    if (!this.chart) return
    this.chart.data.datasets.forEach((ds, i) => { if (matches(ds._meta)) this.chart.getDatasetMeta(i).hidden = hiddenFn ? hiddenFn(ds._meta) : hidden })
    this.chart.update()
  }
}

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// LiveView Hooks
let Hooks = {}

// Hook for auto-updating timestamps
Hooks.TimeAgo = {
  mounted() {
    this.updateTime()
    this.interval = setInterval(() => this.updateTime(), 60000)
  },
  destroyed() {
    clearInterval(this.interval)
  },
  updateTime() {
    const timestamp = this.el.dataset.timestamp
    if (timestamp) {
      const date = new Date(timestamp)
      const now = new Date()
      const diff = Math.floor((now - date) / 1000)

      let timeAgo
      if (diff < 60) {
        timeAgo = "just now"
      } else if (diff < 3600) {
        const mins = Math.floor(diff / 60)
        timeAgo = `${mins}m ago`
      } else if (diff < 86400) {
        const hours = Math.floor(diff / 3600)
        timeAgo = `${hours}h ago`
      } else {
        const days = Math.floor(diff / 86400)
        timeAgo = `${days}d ago`
      }

      this.el.innerText = timeAgo
    }
  }
}

// Hook for countdown timer
Hooks.Countdown = {
  mounted() {
    this.updateCountdown()
    this.interval = setInterval(() => this.updateCountdown(), 1000)
  },
  destroyed() {
    clearInterval(this.interval)
  },
  updateCountdown() {
    const targetTime = parseInt(this.el.dataset.targetTime)
    if (targetTime) {
      const now = Math.floor(Date.now() / 1000)
      const remaining = Math.max(0, targetTime - now)

      const minutes = Math.floor(remaining / 60)
      const seconds = remaining % 60

      this.el.innerText = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
    }
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#06b6d4"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

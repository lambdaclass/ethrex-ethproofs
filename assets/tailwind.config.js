// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/ethproofs_client_web.ex",
    "../lib/ethproofs_client_web/**/*.*ex"
  ],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        brand: "#00d4aa",
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
      },
      keyframes: {
        glow: {
          '0%': { boxShadow: '0 0 5px rgb(6 182 212 / 0.3)' },
          '100%': { boxShadow: '0 0 20px rgb(6 182 212 / 0.5)' },
        }
      }
    },
  },
  plugins: [
    // Allows prefixing tailwind classes with LiveView classes to add transitions
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),
  ]
}

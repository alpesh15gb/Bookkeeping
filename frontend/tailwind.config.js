/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Inter", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"],
        mono: ["JetBrains Mono", "Courier New", "Courier", "monospace"],
      },
      colors: {
        brand: {
          navy:        "#0B1B3D",
          "navy-light": "#0F2247",
          "navy-dark":  "#081328",
          gold:        "#DCA035",
          "gold-hover":"#C98F2C",
          "gold-light": "#FFF8EA",
          // Legacy numeric aliases (keep existing code working)
          50:  "#fcfcfd",
          100: "#f4f4f5",
          200: "#e4e4e7",
          500: "#DCA035",
          600: "#C98F2C",
          700: "#A1711D",
          900: "#0B1B3D",
        },
        navy: {
          50:  "#f5f7fb",
          100: "#ebf0f7",
          800: "#0F2247",
          900: "#0B1B3D",
        },
        gold: {
          50:  "#FFF8EA",
          100: "#FEF9C3",
          500: "#DCA035",
          600: "#C98F2C",
        },
        surface: {
          DEFAULT: "#fcfcfd",
          card:    "#FFFFFF",
          hover:   "#F8F9FC",
        },
      },
      boxShadow: {
        "card": "0 1px 3px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04)",
        "card-elevated": "0 4px 6px rgba(0,0,0,0.05), 0 2px 4px rgba(0,0,0,0.04)",
        "dialog": "0 8px 24px rgba(0,0,0,0.12)",
        // Legacy shadows (keep existing code working)
        sm: "0 1px 2px 0 rgba(0, 0, 0, 0.03)",
        DEFAULT: "0 1px 3px 0 rgba(0, 0, 0, 0.05), 0 1px 2px -1px rgba(0, 0, 0, 0.05)",
        md: "0 4px 6px -1px rgba(0, 0, 0, 0.03), 0 2px 4px -2px rgba(0, 0, 0, 0.03)",
      },
    },
  },
  plugins: [],
}

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
          50: '#fcfcfd',
          100: '#f4f4f5',
          200: '#e4e4e7',
          500: '#DCA035', // Gold accent
          600: '#C98F2C',
          700: '#A1711D',
          900: '#0B1B3D', // Midnight Navy
        },
        navy: {
          50: '#f5f7fb',
          100: '#ebf0f7',
          800: '#0F2247',
          900: '#0B1B3D',
        },
        gold: {
          50: '#FEFCE8',
          100: '#FEF9C3',
          500: '#DCA035',
          600: '#C98F2C',
        }
      },
      boxShadow: {
        sm: '0 1px 2px 0 rgba(0, 0, 0, 0.03)',
        DEFAULT: '0 1px 3px 0 rgba(0, 0, 0, 0.05), 0 1px 2px -1px rgba(0, 0, 0, 0.05)',
        md: '0 4px 6px -1px rgba(0, 0, 0, 0.03), 0 2px 4px -2px rgba(0, 0, 0, 0.03)',
      },
    },
  },
  plugins: [],
}

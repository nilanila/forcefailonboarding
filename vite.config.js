import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import Inspect from 'vite-plugin-inspect'

export default defineConfig({
  plugins: [
    react(),
    Inspect()
  ],
  server: {
    port: 3000
  }
})

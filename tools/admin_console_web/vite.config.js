import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Build statique déployé à la racine du site Firebase Hosting kilimandjaro-admin-dev.
export default defineConfig({
  plugins: [react()],
  build: { outDir: 'dist' },
});

import { fumadocsMdx } from 'fumadocs-mdx/vite';
import { tanstackStart } from '@tanstack/react-start/plugin/vite';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { createRequire } from 'node:module';
import { nitro } from 'nitro/vite';
import { defineConfig } from 'vite';

const tslibPath = createRequire(import.meta.url).resolve('tslib/tslib.es6.js');

export default defineConfig({
	server: {
		port: Number(process.env.PORT) || 3000,
		watch: { ignored: ['**/.output/**'] },
	},
	preview: {
		port: Number(process.env.PORT) || 4173,
	},
	plugins: [
		fumadocsMdx(),
		tailwindcss(),
		tanstackStart({
			prerender: {
				enabled: true,
				filter: (page) => !['/download', '/appcast.xml'].includes(page.path),
				crawlLinks: true,
				autoSubfolderIndex: true,
			},
			pages: [{ path: '/api/search' }],
		}),
		react(),
		nitro({
			preset: process.env.VERCEL ? 'vercel' : 'node-server',
		}),
	],
	resolve: {
		tsconfigPaths: true,
		alias: {
			tslib: tslibPath,
		},
	},
});

import { cloudflareRedirect } from '@ryoppippi/vite-plugin-cloudflare-redirect';
import { defineConfig } from 'vitepress';
import { groupIconMdPlugin, groupIconVitePlugin } from 'vitepress-plugin-group-icons';
import llmstxt from 'vitepress-plugin-llms';

export default defineConfig({
	title: 'Agent Burn',
	description: 'Local subscription value reporting for Claude Code and Codex usage',
	base: '/',
	cleanUrls: true,
	ignoreDeadLinks: true,

	head: [
		['link', { rel: 'icon', href: '/favicon.svg' }],
		['meta', { name: 'theme-color', content: '#646cff' }],
		['meta', { property: 'og:type', content: 'website' }],
		['meta', { property: 'og:locale', content: 'en' }],
		['meta', { property: 'og:title', content: 'Agent Burn | Subscription Value Reports' }],
		['meta', { property: 'og:site_name', content: 'Agent Burn' }],
		[
			'meta',
			{
				property: 'og:image',
				content: 'https://cdn.jsdelivr.net/gh/Melvynx/agent-burn@main/docs/public/logo.png',
			},
		],
		['meta', { property: 'og:url', content: 'https://github.com/Melvynx/agent-burn' }],
	],

	themeConfig: {
		logo: '/logo.svg',

		nav: [
			{ text: 'Guide', link: '/guide/' },
			{
				text: 'Links',
				items: [
					{ text: 'GitHub', link: 'https://github.com/Melvynx/agent-burn' },
					{ text: 'npm', link: 'https://www.npmjs.com/package/agent-burn' },
					{ text: 'Changelog', link: 'https://github.com/Melvynx/agent-burn/releases' },
				],
			},
		],

		sidebar: {
			'/guide/': [
				{
					text: 'Introduction',
					items: [
						{ text: 'Introduction', link: '/guide/' },
						{ text: 'Getting Started', link: '/guide/getting-started' },
						{ text: 'Installation', link: '/guide/installation' },
					],
				},
				{
					text: 'Usage Views',
					items: [
						{ text: 'Summary', link: '/guide/getting-started' },
						{ text: 'Harness', link: '/guide/cli-options#harness' },
					],
				},
				{
					text: 'Data Sources',
					items: [
						{ text: 'Claude Code', link: '/guide/claude/' },
						{ text: 'Codex', link: '/guide/codex/' },
					],
				},
				{
					text: 'Configuration',
					items: [
						{ text: 'Overview', link: '/guide/configuration' },
						{ text: 'Command-Line Options', link: '/guide/cli-options' },
						{ text: 'Environment Variables', link: '/guide/environment-variables' },
						{ text: 'Configuration Files', link: '/guide/config-files' },
					],
				},
				{
					text: 'Integration',
					items: [{ text: 'JSON Output', link: '/guide/json-output' }],
				},
			],
		},

		socialLinks: [
			{ icon: 'github', link: 'https://github.com/Melvynx/agent-burn' },
			{ icon: 'npm', link: 'https://www.npmjs.com/package/agent-burn' },
		],

		footer: {
			message: 'Released under the MIT License.',
			copyright: 'Copyright © 2026 Melvynx',
		},

		search: {
			provider: 'local',
		},

		editLink: {
			pattern: 'https://github.com/Melvynx/agent-burn/edit/main/docs/:path',
			text: 'Edit this page on GitHub',
		},

		lastUpdated: {
			text: 'Updated at',
			formatOptions: {
				year: 'numeric',
				month: '2-digit',
				day: '2-digit',
				hour: '2-digit',
				minute: '2-digit',
				hour12: false,
				timeZone: 'UTC',
			},
		},
	},

	vite: {
		plugins: [
			cloudflareRedirect({
				mode: 'generate',
				entries: [
					{ from: '/gh', to: 'https://github.com/Melvynx/agent-burn', status: 302 },
					{ from: '/npm', to: 'https://www.npmjs.com/package/agent-burn', status: 302 },
					{ from: '/guide/custom-paths', to: '/guide/claude/', status: 301 },
					{ from: '/guide/directory-detection', to: '/guide/claude/', status: 301 },
				],
			}) as any,
			groupIconVitePlugin(),
			...llmstxt(),
		],
	},

	markdown: {
		config(md) {
			// eslint-disable-next-line ts/no-unsafe-argument -- markdown-it type mismatch between vitepress and plugin
			md.use(groupIconMdPlugin as any);
		},
	},
});

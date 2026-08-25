export type DocsSearchEntry = {
	url: string;
	title: string;
	description: string;
	folder: string;
};

export type DocsNavLink = {
	title: string;
	href: string;
};

export type DocsNavFolder = {
	name: string;
	items: readonly DocsNavLink[];
};

export const docsTopLevel = [
	{ name: 'Introduction', href: '/docs' },
	{ name: 'Getting Started', href: '/docs/getting-started' },
	{ name: 'Installation', href: '/docs/installation' },
] as const satisfies readonly { name: string; href: string }[];

export const docsFolders = [
	{
		name: 'Commands',
		items: [
			{ title: 'CLI Options', href: '/docs/cli-options' },
			{ title: 'JSON Output', href: '/docs/json-output' },
		],
	},
	{
		name: 'Data sources',
		items: [
			{ title: 'Claude Code', href: '/docs/claude' },
			{ title: 'Codex', href: '/docs/codex' },
			{ title: 'Cursor', href: '/docs/cursor' },
		],
	},
	{
		name: 'Configuration',
		items: [
			{ title: 'Configuration', href: '/docs/configuration' },
			{ title: 'Environment Variables', href: '/docs/environment-variables' },
			{ title: 'Configuration Files', href: '/docs/config-files' },
		],
	},
] as const satisfies readonly DocsNavFolder[];

export const docsSearchIndex = [
	{
		url: '/docs',
		title: 'Documentation',
		description: 'Local subscription-value reports for Claude Code, Codex, and Cursor.',
		folder: '',
	},
	{
		url: '/docs/getting-started',
		title: 'Getting Started',
		description: 'Run the local usage overview and add subscription value.',
		folder: '',
	},
	{
		url: '/docs/installation',
		title: 'Installation',
		description: 'Run Agent Burn with npx, pnpm, bun, or Nix.',
		folder: '',
	},
	{
		url: '/docs/cli-options',
		title: 'CLI Options',
		description: 'Public flags for summary, harness, and shared output.',
		folder: 'Commands',
	},
	{
		url: '/docs/json-output',
		title: 'JSON Output',
		description: 'Machine-readable reports for dashboards and scripts.',
		folder: 'Commands',
	},
	{
		url: '/docs/claude',
		title: 'Claude Code',
		description: 'Weekly harness and local log locations for Claude Code.',
		folder: 'Data sources',
	},
	{
		url: '/docs/codex',
		title: 'Codex',
		description: 'Weekly harness and local log locations for Codex.',
		folder: 'Data sources',
	},
	{
		url: '/docs/cursor',
		title: 'Cursor',
		description: 'Cursor usage in the summary view, including charts and HTML.',
		folder: 'Data sources',
	},
	{
		url: '/docs/configuration',
		title: 'Configuration',
		description: 'JSON defaults that CLI flags can still override.',
		folder: 'Configuration',
	},
	{
		url: '/docs/environment-variables',
		title: 'Environment Variables',
		description: 'Override local data-directory detection.',
		folder: 'Configuration',
	},
	{
		url: '/docs/config-files',
		title: 'Configuration Files',
		description: 'Load a specific JSON file with --config.',
		folder: 'Configuration',
	},
] as const satisfies readonly DocsSearchEntry[];

export const docsPageOrder: readonly DocsNavLink[] = docsSearchIndex.map((page) => ({
	title: page.title,
	href: page.url,
}));

export function docsSplat(href: string) {
	return href === '/docs' ? '' : href.replace(/^\/docs\//, '');
}

export function getDocsNeighbours(href: string) {
	const index = docsPageOrder.findIndex((page) => page.href === href);
	if (index < 0) return { previous: null, next: null };

	return {
		previous: index > 0 ? docsPageOrder[index - 1] : null,
		next: index < docsPageOrder.length - 1 ? docsPageOrder[index + 1] : null,
	};
}

export function isDocsHrefActive(href: string, pathname: string) {
	if (href === '/docs') return pathname === '/docs' || pathname === '/docs/';
	return pathname === href || pathname.startsWith(`${href}/`);
}

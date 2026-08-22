export const appName = 'Agent Burn';
export const siteUrl = 'https://agent-burn.melvynx.dev';
export const docsRoute = '/docs';
export const installCommand = 'npx agent-burn@latest summary --value';

export const gitConfig = {
	user: 'Melvynx',
	repo: 'agent-burn',
	branch: 'main',
} as const satisfies { user: string; repo: string; branch: string };

export const githubUrl = `https://github.com/${gitConfig.user}/${gitConfig.repo}`;
export const npmUrl = 'https://www.npmjs.com/package/agent-burn';

export function encodeMarkdownUrl(slugs: string[], locale?: string) {
	const segments = [...slugs];
	if (segments.length === 0) {
		segments.push('index.md');
	} else {
		const last = segments.at(-1);
		if (last) {
			segments[segments.length - 1] = `${last}.md`;
		}
	}

	return `/${[locale, ...docsRoute.split('/'), ...segments].filter(Boolean).join('/')}`;
}

export function decodeMarkdownUrl(segments: string[]) {
	if (segments.length === 0) return [];

	const out = [...segments];
	const last = out.at(-1);
	if (last) {
		out[out.length - 1] = last.replace(/\.md$/, '');
	}
	if (out.length === 1 && out[0] === 'index') out.pop();
	return out;
}

import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';
import { appName, githubUrl } from './shared.ts';

export function baseOptions(): BaseLayoutProps {
	return {
		nav: {
			title: (
				<span className="inline-flex items-center gap-2">
					<img src="/logo.svg" alt="" width={22} height={22} className="rounded-[6px]" />
					{appName}
				</span>
			),
		},
		githubUrl,
		links: [
			{
				text: 'Home',
				url: '/',
			},
			{
				text: 'npm',
				url: 'https://www.npmjs.com/package/agent-burn',
				external: true,
			},
		],
	};
}

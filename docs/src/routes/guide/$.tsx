import { createFileRoute, redirect } from '@tanstack/react-router';

const aliases = {
	'custom-paths': '/docs/claude',
	'directory-detection': '/docs/claude',
} as const satisfies Record<string, string>;

export const Route = createFileRoute('/guide/$')({
	beforeLoad: ({ params }) => {
		const splat = params._splat ?? '';
		const alias = splat in aliases ? aliases[splat as keyof typeof aliases] : undefined;
		throw redirect({
			href: alias ?? `/docs/${splat}`,
		});
	},
});

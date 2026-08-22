import { githubUrl } from '@/lib/shared.ts';
import { createFileRoute, redirect } from '@tanstack/react-router';

export const Route = createFileRoute('/gh')({
	beforeLoad: () => {
		throw redirect({ href: githubUrl });
	},
});

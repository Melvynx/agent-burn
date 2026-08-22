import { npmUrl } from '@/lib/shared.ts';
import { createFileRoute, redirect } from '@tanstack/react-router';

export const Route = createFileRoute('/npm')({
	beforeLoad: () => {
		throw redirect({ href: npmUrl });
	},
});

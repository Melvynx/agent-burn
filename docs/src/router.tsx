import { NotFound } from '@/components/not-found.tsx';
import { createRouter as createTanStackRouter } from '@tanstack/react-router';
import { routeTree } from './routeTree.gen.ts';

export function getRouter() {
	return createTanStackRouter({
		routeTree,
		defaultPreload: 'intent',
		scrollRestoration: true,
		defaultNotFoundComponent: NotFound,
	});
}

declare module '@tanstack/react-router' {
	interface Register {
		router: ReturnType<typeof getRouter>;
	}
}

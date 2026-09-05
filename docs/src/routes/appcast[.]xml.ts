import { createFileRoute } from '@tanstack/react-router';

// Keep the Mac release channel independent of the npm CLI release tags.
export const Route = createFileRoute('/appcast.xml')({
	server: {
		handlers: {
			GET: () =>
				new Response(null, {
					status: 302,
					headers: {
						Location:
							'https://github.com/Melvynx/agent-burn/releases/download/macos/appcast.xml',
						'Cache-Control': 'no-store',
					},
				}),
		},
	},
});

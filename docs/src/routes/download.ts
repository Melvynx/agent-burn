import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/download')({
	server: {
		handlers: {
			GET: () =>
				new Response(null, {
					status: 302,
					headers: {
						Location:
							'https://github.com/Melvynx/agent-burn/releases/download/macos/Agent-Burn-macOS.zip',
						'Cache-Control': 'no-store',
					},
				}),
		},
	},
});

import { createFileRoute } from '@tanstack/react-router';

// Keep the Mac release channel independent of the npm CLI release tags.
export const Route = createFileRoute('/appcast.xml')({
	server: {
		handlers: {
			GET: async () => {
				const target =
					'https://github.com/Melvynx/agent-burn/releases/download/macos/appcast.xml';
				try {
					const response = await fetch(target, {
						method: 'HEAD',
						signal: AbortSignal.timeout(8000),
					});
					if (response.status === 404) {
						return new Response(
							'<?xml version="1.0"?><rss version="2.0"><channel><title>Agent Burn</title><description>Signed macOS updates</description></channel></rss>',
							{
								headers: {
									'Content-Type': 'application/rss+xml; charset=utf-8',
									'Cache-Control': 'no-store',
								},
							},
						);
					}
					if (!response.ok)
						return new Response('Update service temporarily unavailable', {
							status: 503,
							headers: { 'Cache-Control': 'no-store' },
						});
					return new Response(null, {
						status: 302,
						headers: { Location: target, 'Cache-Control': 'no-store' },
					});
				} catch {
					return new Response('Update service temporarily unavailable', {
						status: 503,
						headers: { 'Cache-Control': 'no-store' },
					});
				}
			},
		},
	},
});

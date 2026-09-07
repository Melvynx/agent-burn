import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/download')({
	server: {
		handlers: {
			GET: async () => {
				const target =
					'https://github.com/Melvynx/agent-burn/releases/download/macos/Agent-Burn-macOS.zip';
				let available = false;
				try {
					const response = await fetch(target, {
						method: 'HEAD',
						signal: AbortSignal.timeout(8000),
					});
					available = response.ok;
				} catch {
					/* Keep installation guidance available during upstream outages. */
				}
				if (!available)
					return new Response(
						`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Agent Burn for Mac</title><style>body{color:#f5f5f5;background:#141312;font:17px/1.7 system-ui;margin:0;padding:10vh 24px}main{max-width:620px;margin:auto}h1{font-size:42px;line-height:1.1;letter-spacing:-.03em}p{color:#bdb9b5}a{color:#efb16c}code{display:block;padding:18px;background:#242220;border-radius:9px;overflow-wrap:anywhere;font-size:14px}</style><main><a href="/">← Agent Burn</a><h1>The Mac download is being finalized.</h1><p>The first public download is awaiting Apple notarization. If a published download is temporarily unavailable, please try again shortly.</p><p>The native app and release scripts are already open source. You can build the app yourself, or use the CLI now:</p><code>npx agent-burn@latest summary --value</code><p><a href="https://github.com/Melvynx/agent-burn/tree/codex/macos-product-release/apps/macos">Build the Mac app from source</a> · <a href="/docs">Read the documentation</a></p></main></html>`,
						{
							status: 503,
							headers: {
								'Content-Type': 'text/html; charset=utf-8',
								'Cache-Control': 'no-store',
								'Retry-After': '3600',
							},
						},
					);
				return new Response(null, {
					status: 302,
					headers: {
						Location:
							'https://github.com/Melvynx/agent-burn/releases/download/macos/Agent-Burn-macOS.zip',
						'Cache-Control': 'no-store',
					},
				});
			},
		},
	},
});

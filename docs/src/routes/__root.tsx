import {
	HeadContent,
	Outlet,
	Scripts,
	createRootRoute,
} from '@tanstack/react-router';
import { RootProvider } from 'fumadocs-ui/provider/tanstack';
import appCss from '../styles/app.css?url';
import landingCss from '../styles/landing.css?url';
import { siteUrl } from '../lib/shared.ts';

const title = 'Agent Burn — Your AI usage, in view.';
const description =
	'A native macOS app and open-source CLI for Codex, Claude, Cursor and more. Track spend, subscription limits and daily usage history.';

export const Route = createRootRoute({
	head: () => ({
		meta: [
			{ charSet: 'utf-8' },
			{ name: 'viewport', content: 'width=device-width, initial-scale=1' },
			{ title },
			{ name: 'description', content: description },
			{ name: 'theme-color', content: '#16120e' },
			{ property: 'og:type', content: 'website' },
			{ property: 'og:site_name', content: 'Agent Burn' },
			{ property: 'og:title', content: title },
			{ property: 'og:description', content: description },
			{ property: 'og:url', content: siteUrl },
			{ property: 'og:image', content: `${siteUrl}/product/dashboard.png` },
			{ name: 'twitter:card', content: 'summary_large_image' },
		],
		links: [
			{ rel: 'stylesheet', href: appCss },
			{ rel: 'stylesheet', href: landingCss },
			{ rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml' },
			{ rel: 'canonical', href: siteUrl },
		],
	}),
	component: RootLayout,
});

function RootLayout() {
	return (
		<html lang="en" className="dark" suppressHydrationWarning>
			<head>
				<HeadContent />
			</head>
			<body className="flex min-h-screen flex-col">
				<a className="skip-link" href="#main-content">
					Skip to content
				</a>
				<RootProvider
					theme={{ defaultTheme: 'dark', enabled: false }}
					search={{ enabled: false }}
				>
					<Outlet />
				</RootProvider>
				<Scripts />
			</body>
		</html>
	);
}

import { useState, type ReactNode } from 'react';
import { DocsChrome, DocsMobileDrawer } from './docs-chrome.tsx';
import { DocsSearchDialog, DocsSearchProvider } from './docs-search.tsx';
import { DocsSidebar } from './docs-sidebar.tsx';

export function DocsShell({ children }: { children: ReactNode }) {
	const [menuOpen, setMenuOpen] = useState(false);

	return (
		<DocsSearchProvider>
			<div className="docs-shell dark flex min-h-screen flex-col bg-[#08090a] font-sans text-[#f7f8f8] antialiased selection:bg-white/20">
				<DocsChrome menuOpen={menuOpen} onMenuOpenChange={setMenuOpen} />
				<div className="flex w-full flex-1 flex-col pt-16">
					<div className="flex w-full flex-1 border-t border-white/[0.06]">
						<DocsSidebar />
						<main id="main-content" className="min-w-0 flex-1">
							{children}
						</main>
					</div>
				</div>
				<DocsMobileDrawer open={menuOpen} onClose={() => setMenuOpen(false)} />
				<DocsSearchDialog />
			</div>
		</DocsSearchProvider>
	);
}

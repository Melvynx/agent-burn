import { docsSearchIndex, docsSplat, type DocsSearchEntry } from '@/lib/docs-nav.ts';
import { useNavigate } from '@tanstack/react-router';
import { CornerDownLeft, FileText, Search } from 'lucide-react';
import {
	createContext,
	use,
	useEffect,
	useMemo,
	useState,
	type ReactNode,
} from 'react';

type DocsSearchContextValue = {
	open: boolean;
	setOpen: (open: boolean) => void;
};

const DocsSearchContext = createContext<DocsSearchContextValue | null>(null);

function getMatchScore(text: string, query: string) {
	const normalized = text.toLowerCase();
	if (normalized === query) return 100;
	if (normalized.startsWith(query)) return 75;
	if (normalized.includes(query)) return 25;
	return 0;
}

export function DocsSearchProvider({ children }: { children: ReactNode }) {
	const [open, setOpen] = useState(false);

	useEffect(() => {
		function onKeyDown(event: KeyboardEvent) {
			if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
				event.preventDefault();
				setOpen((current) => !current);
			}
		}

		window.addEventListener('keydown', onKeyDown);
		return () => window.removeEventListener('keydown', onKeyDown);
	}, []);

	return <DocsSearchContext value={{ open, setOpen }}>{children}</DocsSearchContext>;
}

function useDocsSearch() {
	const context = use(DocsSearchContext);
	if (!context) throw new Error('DocsSearchProvider is required');
	return context;
}

export function DocsSearchTrigger() {
	const { setOpen } = useDocsSearch();

	return (
		<div className="w-full px-3 pt-4 pb-2">
			<button
				type="button"
				onClick={() => setOpen(true)}
				className="flex w-full items-center gap-2 rounded-md border border-white/[0.08] bg-white/[0.04] px-2.5 py-1.5 text-sm text-[#8a8f98] transition-colors hover:border-white/20 hover:bg-white/[0.07] hover:text-[#f7f8f8] focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none"
			>
				<Search aria-hidden="true" className="size-3.5 shrink-0" />
				<span className="flex-1 text-left">Search docs...</span>
				<kbd className="rounded border border-white/10 px-1.5 py-0.5 font-mono text-[10px] text-[#8a8f98]">
					⌘K
				</kbd>
			</button>
		</div>
	);
}

export function DocsSearchDialog() {
	const { open, setOpen } = useDocsSearch();
	const navigate = useNavigate();
	const [query, setQuery] = useState('');

	const results = useMemo(() => {
		const q = query.toLowerCase().trim();
		if (!q || q.length < 2) return [];

		return docsSearchIndex
			.map((doc) => {
				const score = Math.max(getMatchScore(doc.title, q), getMatchScore(doc.description, q));
				return { ...doc, score };
			})
			.filter((doc) => doc.score > 0)
			.sort((a, b) => b.score - a.score || a.title.localeCompare(b.title))
			.slice(0, 12);
	}, [query]);

	useEffect(() => {
		if (!open) setQuery('');
	}, [open]);

	useEffect(() => {
		if (!open) return;

		function onKeyDown(event: KeyboardEvent) {
			if (event.key === 'Escape') setOpen(false);
		}

		window.addEventListener('keydown', onKeyDown);
		return () => window.removeEventListener('keydown', onKeyDown);
	}, [open, setOpen]);

	if (!open) return null;

	function goTo(entry: DocsSearchEntry) {
		void navigate({ to: '/docs/$', params: { _splat: docsSplat(entry.url) } });
		setOpen(false);
	}

	return (
		<div className="fixed inset-0 z-[80] flex items-start justify-center bg-black/70 px-4 pt-[12vh]">
			<button
				type="button"
				className="absolute inset-0 cursor-default"
				aria-label="Close search"
				onClick={() => setOpen(false)}
			/>
			<div
				role="dialog"
				aria-modal="true"
				aria-label="Search documentation"
				className="relative z-10 w-full max-w-xl overflow-hidden rounded-xl bg-neutral-900 p-2 pb-11 shadow-2xl ring-4 ring-neutral-800"
			>
				<input
					autoFocus
					value={query}
					onChange={(event) => setQuery(event.target.value)}
					placeholder="Search documentation..."
					className="w-full rounded-md bg-transparent px-3 py-2.5 text-sm text-[#f7f8f8] outline-none placeholder:text-[#8a8f98]"
				/>
				<div className="no-scrollbar min-h-80 overflow-y-auto">
					{query.trim().length < 2 ? (
						<div className="flex flex-col gap-1 p-1">
							<p className="px-3 py-2 font-mono text-[10px] tracking-[0.12em] text-white/40 uppercase">
								Quick Links
							</p>
							{docsSearchIndex
								.filter((entry) => entry.folder === '')
								.map((entry) => (
									<button
										key={entry.url}
										type="button"
										onClick={() => goTo(entry)}
										className="flex items-center gap-3 rounded-md px-3 py-2 text-left text-sm text-[#f7f8f8] hover:bg-white/[0.06]"
									>
										<FileText className="size-4 text-[#8a8f98]" />
										{entry.title}
									</button>
								))}
						</div>
					) : results.length === 0 ? (
						<p className="px-3 py-12 text-center text-sm text-[#8a8f98]">No results found.</p>
					) : (
						<div className="flex flex-col gap-1 p-1">
							<p className="px-3 py-2 font-mono text-[10px] tracking-[0.12em] text-white/40 uppercase">
								Documentation
							</p>
							{results.map((entry) => (
								<button
									key={entry.url}
									type="button"
									onClick={() => goTo(entry)}
									className="flex items-start gap-3 rounded-md px-3 py-2 text-left hover:bg-white/[0.06]"
								>
									<FileText className="mt-0.5 size-4 shrink-0 text-[#8a8f98]" />
									<span className="min-w-0">
										<span className="block truncate text-sm font-medium text-[#f7f8f8]">
											{entry.title}
										</span>
										{entry.folder ? (
											<span className="block truncate text-xs text-[#8a8f98]">{entry.folder}</span>
										) : null}
									</span>
								</button>
							))}
						</div>
					)}
				</div>
				<div className="absolute inset-x-0 bottom-0 flex h-10 items-center gap-2 rounded-b-xl border-t border-neutral-700 bg-neutral-800 px-4 text-xs text-[#8a8f98]">
					<CornerDownLeft className="size-3" />
					Go to Page
				</div>
			</div>
		</div>
	);
}

export function DocsMobileSearchButton() {
	const { setOpen } = useDocsSearch();

	return (
		<button
			type="button"
			onClick={() => setOpen(true)}
			className="inline-flex size-8 items-center justify-center rounded-md text-[#8a8f98] hover:bg-white/[0.04] hover:text-[#f7f8f8] lg:hidden"
			aria-label="Search docs"
		>
			<Search className="size-4" />
		</button>
	);
}


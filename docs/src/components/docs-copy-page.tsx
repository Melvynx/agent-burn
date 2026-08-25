import { cn } from '@/lib/cn.ts';
import { Check, ChevronDown, Copy } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

function promptUrl(baseURL: string, url: string) {
	return `${baseURL}?q=${encodeURIComponent(
		`I'm looking at this Agent Burn documentation: ${url}.
Help me understand how to use it. Be ready to explain concepts, give examples, or help debug based on it.`,
	)}`;
}

export function DocsCopyPage({
	markdownUrl,
	pageUrl,
	markdown,
	githubUrl,
}: {
	markdownUrl: string;
	pageUrl: string;
	markdown: string;
	githubUrl: string;
}) {
	const [copied, setCopied] = useState(false);
	const [open, setOpen] = useState(false);
	const rootRef = useRef<HTMLDivElement>(null);

	useEffect(() => {
		if (!copied) return;
		const timer = window.setTimeout(() => setCopied(false), 1600);
		return () => window.clearTimeout(timer);
	}, [copied]);

	useEffect(() => {
		if (!open) return;

		function onPointerDown(event: MouseEvent) {
			if (rootRef.current && !rootRef.current.contains(event.target as Node)) {
				setOpen(false);
			}
		}

		function onKeyDown(event: KeyboardEvent) {
			if (event.key === 'Escape') setOpen(false);
		}

		document.addEventListener('mousedown', onPointerDown);
		document.addEventListener('keydown', onKeyDown);
		return () => {
			document.removeEventListener('mousedown', onPointerDown);
			document.removeEventListener('keydown', onKeyDown);
		};
	}, [open]);

	async function copyPage() {
		let text = markdown.trim();
		if (!text) {
			const response = await fetch(markdownUrl);
			text = await response.text();
		}

		try {
			await navigator.clipboard.writeText(text);
		} catch {
			const field = document.createElement('textarea');
			field.value = text;
			field.setAttribute('readonly', '');
			field.style.position = 'fixed';
			field.style.left = '-9999px';
			document.body.append(field);
			field.select();
			document.execCommand('copy');
			field.remove();
		}
		setCopied(true);
	}

	return (
		<div ref={rootRef} className="relative">
			<div className="flex overflow-hidden rounded-lg border border-white/[0.08] bg-white/[0.04]">
				<button
					type="button"
					onClick={() => void copyPage()}
					className="inline-flex h-8 items-center gap-1.5 px-2.5 text-[13px] text-[#f7f8f8] hover:bg-white/[0.06]"
				>
					{copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
					Copy Page
				</button>
				<span className="w-px self-stretch bg-white/[0.08]" />
				<button
					type="button"
					aria-expanded={open}
					aria-label="More page options"
					onClick={() => setOpen((current) => !current)}
					className="inline-flex size-8 items-center justify-center text-[#8a8f98] hover:bg-white/[0.06] hover:text-[#f7f8f8]"
				>
					<ChevronDown className={cn('size-4 transition-transform', open && 'rotate-180')} />
				</button>
			</div>
			{open ? (
				<div className="absolute top-full right-0 z-20 mt-2 w-52 rounded-lg border border-white/[0.08] bg-[#0d0e10] p-1 shadow-xl shadow-black/40">
					<a
						href={markdownUrl}
						target="_blank"
						rel="noopener noreferrer"
						className="flex items-center gap-2 rounded-md px-3 py-2 text-sm text-[#f7f8f8] hover:bg-white/[0.04]"
					>
						View as Markdown
					</a>
					<a
						href={promptUrl('https://chatgpt.com', pageUrl)}
						target="_blank"
						rel="noopener noreferrer"
						className="flex items-center gap-2 rounded-md px-3 py-2 text-sm text-[#f7f8f8] hover:bg-white/[0.04]"
					>
						Open in ChatGPT
					</a>
					<a
						href={promptUrl('https://claude.ai/new', pageUrl)}
						target="_blank"
						rel="noopener noreferrer"
						className="flex items-center gap-2 rounded-md px-3 py-2 text-sm text-[#f7f8f8] hover:bg-white/[0.04]"
					>
						Open in Claude
					</a>
					<a
						href={githubUrl}
						target="_blank"
						rel="noopener noreferrer"
						className="flex items-center gap-2 rounded-md px-3 py-2 text-sm text-[#f7f8f8] hover:bg-white/[0.04]"
					>
						Open on GitHub
					</a>
				</div>
			) : null}
		</div>
	);
}

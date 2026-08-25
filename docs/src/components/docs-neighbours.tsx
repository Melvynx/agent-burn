import { docsSplat, type DocsNavLink } from '@/lib/docs-nav.ts';
import { Link } from '@tanstack/react-router';
import { ArrowLeft, ArrowRight } from 'lucide-react';

export function DocsNeighbours({
	previous,
	next,
}: {
	previous: DocsNavLink | null;
	next: DocsNavLink | null;
}) {
	return (
		<div className="grid grid-cols-1 gap-3 border-t border-white/[0.06] pt-8 sm:grid-cols-2">
			{previous ? (
				<Link
					to="/docs/$"
					params={{ _splat: docsSplat(previous.href) }}
					className="group flex flex-col gap-1 rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 transition-colors hover:border-white/20 hover:bg-white/[0.04] focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none"
				>
					<span className="flex items-center gap-1 font-mono text-[10px] tracking-[0.12em] text-white/40 uppercase">
						<ArrowLeft className="size-3" />
						Previous
					</span>
					<span className="text-sm font-medium text-[#f7f8f8]">{previous.title}</span>
				</Link>
			) : (
				<div />
			)}
			{next ? (
				<Link
					to="/docs/$"
					params={{ _splat: docsSplat(next.href) }}
					className="group flex flex-col items-end gap-1 rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 text-right transition-colors hover:border-white/20 hover:bg-white/[0.04] focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none"
				>
					<span className="flex items-center gap-1 font-mono text-[10px] tracking-[0.12em] text-white/40 uppercase">
						Next
						<ArrowRight className="size-3" />
					</span>
					<span className="text-sm font-medium text-[#f7f8f8]">{next.title}</span>
				</Link>
			) : null}
		</div>
	);
}

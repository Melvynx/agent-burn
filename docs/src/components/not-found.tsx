import { DocsShell } from '@/components/docs-shell.tsx';
import { Link } from '@tanstack/react-router';

export function NotFound() {
	return (
		<DocsShell>
			<div className="mx-auto flex max-w-prose flex-col gap-4 px-6 py-20">
				<h1 className="text-[2rem] font-medium tracking-[-0.025em] text-[#f7f8f8]">
					Page not found
				</h1>
				<p className="text-lg text-[#8a8f98]">That page is not part of Agent Burn.</p>
				<Link
					to="/docs/$"
					params={{ _splat: '' }}
					className="text-sm text-[#f7f8f8] underline decoration-white/30 underline-offset-2 hover:decoration-white"
				>
					Back to docs
				</Link>
			</div>
		</DocsShell>
	);
}

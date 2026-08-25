import { cn } from '@/lib/cn.ts';
import { useEffect, useMemo, useState, type ReactNode } from 'react';

export type DocsTocItem = {
	title: ReactNode;
	url: string;
	depth: number;
};

function useActiveItem(itemIds: string[]) {
	const [activeId, setActiveId] = useState<string | null>(null);

	useEffect(() => {
		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) setActiveId(entry.target.id);
				}
			},
			{ rootMargin: '0% 0% -80% 0%' },
		);

		for (const id of itemIds) {
			const element = document.getElementById(id);
			if (element) observer.observe(element);
		}

		return () => observer.disconnect();
	}, [itemIds]);

	return activeId;
}

export function DocsTableOfContents({ toc }: { toc: DocsTocItem[] }) {
	const itemIds = useMemo(() => toc.map((item) => item.url.replace('#', '')), [toc]);
	const activeHeading = useActiveItem(itemIds);

	if (toc.length === 0) return null;

	return (
		<div className="flex flex-col gap-3">
			<h4 className="font-mono text-[10px] tracking-[0.12em] text-white/40 uppercase">
				On This Page
			</h4>
			<nav className="flex flex-col gap-2">
				{toc.map((item, index) => (
					<a
						key={`${item.url}-${index}`}
						href={item.url}
						className={cn(
							'block text-[13px] text-[#8a8f98] no-underline transition-colors hover:text-[#f7f8f8]',
							item.url === `#${activeHeading}` && 'font-medium text-[#f7f8f8]',
							item.depth === 3 && 'pl-4',
							item.depth >= 4 && 'pl-6',
						)}
					>
						{item.title}
					</a>
				))}
			</nav>
		</div>
	);
}

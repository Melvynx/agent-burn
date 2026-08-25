import { cn } from '@/lib/cn.ts';
import {
	docsFolders,
	docsSplat,
	docsTopLevel,
	isDocsHrefActive,
} from '@/lib/docs-nav.ts';
import { Link, useRouterState } from '@tanstack/react-router';
import { BookOpen, Download, Rocket } from 'lucide-react';
import { DocsSearchTrigger } from './docs-search.tsx';

const topLevelIcons = {
	Introduction: BookOpen,
	'Getting Started': Rocket,
	Installation: Download,
} as const;

export function DocsSidebar() {
	return (
		<aside className="no-scrollbar sticky top-16 hidden h-[calc(100vh-4rem)] w-64 shrink-0 overflow-y-auto border-r border-white/[0.06] lg:block">
			<DocsSidebarNav />
		</aside>
	);
}

export function DocsSidebarNav({ onNavigate }: { onNavigate?: () => void }) {
	const pathname = useRouterState({ select: (state) => state.location.pathname });

	return (
		<>
			<DocsSearchTrigger />
			<nav className="flex flex-col gap-7 px-3 pt-2 pb-16">
				<div className="flex flex-col gap-0.5">
					{docsTopLevel.map(({ name, href }) => {
						const Icon = topLevelIcons[name];
						const isActive = isDocsHrefActive(href, pathname);
						return (
							<Link
								key={href}
								to="/docs/$"
								params={{ _splat: docsSplat(href) }}
								onClick={onNavigate}
								className={cn(
									'flex items-center gap-2.5 rounded-md px-2 py-1.5 text-sm transition-colors focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none',
									isActive
										? 'bg-white/[0.06] font-medium text-[#f7f8f8]'
										: 'text-[#8a8f98] hover:bg-white/[0.03] hover:text-[#f7f8f8]',
								)}
							>
								<Icon
									className={cn(
										'size-3.5 shrink-0',
										isActive ? 'text-[#f7f8f8]' : 'text-[#8a8f98]/70',
									)}
								/>
								{name}
							</Link>
						);
					})}
				</div>

				{docsFolders.map((folder) => (
					<div key={folder.name} className="flex flex-col gap-1.5">
						<h4 className="px-2 pb-1 font-mono text-[10px] tracking-[0.12em] text-white/40 uppercase">
							{folder.name}
						</h4>
						<div className="ml-2 flex flex-col gap-px border-l border-white/[0.06]">
							{folder.items.map((item) => {
								const isActive = isDocsHrefActive(item.href, pathname);
								return (
									<Link
										key={item.href}
										to="/docs/$"
										params={{ _splat: docsSplat(item.href) }}
										onClick={onNavigate}
										className={cn(
											'-ml-px flex items-center gap-1.5 rounded-r-md border-l py-1 pr-2 pl-3 text-[13px] transition-colors focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none',
											isActive
												? 'border-[#f7f8f8] font-medium text-[#f7f8f8]'
												: 'border-transparent text-[#8a8f98] hover:border-white/25 hover:text-[#f7f8f8]',
										)}
									>
										<span className="truncate">{item.title}</span>
									</Link>
								);
							})}
						</div>
					</div>
				))}
			</nav>
		</>
	);
}

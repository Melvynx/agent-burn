import { cn } from '@/lib/cn.ts';
import { docsSplat } from '@/lib/docs-nav.ts';
import { Link } from '@tanstack/react-router';
import {
	BookOpen,
	Bot,
	Download,
	FileText,
	MousePointer2,
	Play,
	Settings,
	SquareTerminal,
	Terminal,
	type LucideIcon,
} from 'lucide-react';
import type { ReactNode } from 'react';

const icons = {
	BookOpen,
	Bot,
	Download,
	FileText,
	MousePointer2,
	Play,
	Settings,
	SquareTerminal,
	Terminal,
} as const satisfies Record<string, LucideIcon>;

export function DocCard({
	href,
	icon,
	title,
	description,
}: {
	href: string;
	icon: keyof typeof icons;
	title: string;
	description: string;
}) {
	const Icon = icons[icon] ?? FileText;

	return (
		<Link
			to="/docs/$"
			params={{ _splat: docsSplat(href) }}
			className={cn(
				'group flex flex-col gap-3 rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 no-underline',
				'transition-colors hover:border-white/20 hover:bg-white/[0.04]',
			)}
		>
			<Icon className="size-5 text-[#8a8f98]" />
			<div className="flex flex-col gap-0.5">
				<span className="text-sm font-medium text-[#f7f8f8]">{title}</span>
				<span className="text-[13px] leading-snug text-[#8a8f98]">{description}</span>
			</div>
		</Link>
	);
}

export function DocCardGrid({ children }: { children: ReactNode }) {
	return <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">{children}</div>;
}

export function DocSection({ title, children }: { title: string; children: ReactNode }) {
	return (
		<section className="flex flex-col gap-3">
			<p className="m-0 font-mono text-[10px] tracking-[0.12em] text-white/40 uppercase">{title}</p>
			{children}
		</section>
	);
}

export function DocCardWrapper({ children }: { children: ReactNode }) {
	return <div className="not-prose mt-2 flex flex-col gap-8">{children}</div>;
}

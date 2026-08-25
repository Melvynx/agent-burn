import { GithubMark, LogoLockup } from '@/components/logo.tsx';
import { cn } from '@/lib/cn.ts';
import { githubUrl } from '@/lib/shared.ts';
import { Link, useRouterState } from '@tanstack/react-router';
import { Menu, X } from 'lucide-react';
import { useEffect, useState } from 'react';
import { DocsMobileSearchButton } from './docs-search.tsx';
import { DocsSidebarNav } from './docs-sidebar.tsx';

const navLinks = [
	{ label: 'Why', href: '/#cost' },
	{ label: 'Commands', href: '/#commands' },
	{ label: 'Sources', href: '/#sources' },
	{ label: 'Docs', href: '/docs' },
] as const satisfies readonly { label: string; href: string }[];

export function DocsChrome({
	menuOpen,
	onMenuOpenChange,
}: {
	menuOpen: boolean;
	onMenuOpenChange: (open: boolean) => void;
}) {
	const pathname = useRouterState({ select: (state) => state.location.pathname });
	const [isScrolled, setIsScrolled] = useState(false);

	useEffect(() => {
		function updateScrollState() {
			setIsScrolled(window.scrollY > 8);
		}

		updateScrollState();
		window.addEventListener('scroll', updateScrollState, { passive: true });
		return () => window.removeEventListener('scroll', updateScrollState);
	}, []);

	useEffect(() => {
		onMenuOpenChange(false);
	}, [pathname, onMenuOpenChange]);

	return (
		<header
			className={cn(
				'fixed inset-x-0 top-0 z-50 border-b transition-colors duration-200',
				isScrolled
					? 'border-white/[0.08] bg-[#08090a]/80 backdrop-blur-xl'
					: 'border-transparent bg-[#08090a]',
			)}
		>
			<nav className="mx-auto flex h-16 w-full max-w-6xl items-center gap-8 px-6">
				<Link
					to="/"
					className="text-[15px] font-medium tracking-[-0.02em] text-[#f7f8f8] focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none"
				>
					<LogoLockup />
				</Link>

				<div className="hidden items-center gap-1 md:flex">
					{navLinks.map((link) => {
						const isDocs = link.href === '/docs';
						const isActive = isDocs && (pathname === '/docs' || pathname.startsWith('/docs/'));

						if (isDocs) {
							return (
								<Link
									key={link.href}
									to="/docs/$"
									params={{ _splat: '' }}
									className={cn(
										'rounded-md px-3 py-1.5 text-sm transition-colors focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none',
										isActive ? 'text-[#f7f8f8]' : 'text-[#8a8f98] hover:text-[#f7f8f8]',
									)}
								>
									{link.label}
								</Link>
							);
						}

						return (
							<a
								key={link.href}
								href={link.href}
								className="rounded-md px-3 py-1.5 text-sm text-[#8a8f98] transition-colors hover:text-[#f7f8f8] focus-visible:ring-2 focus-visible:ring-white/40 focus-visible:outline-none"
							>
								{link.label}
							</a>
						);
					})}
				</div>

				<div className="ml-auto flex items-center gap-2">
					<DocsMobileSearchButton />
					<a
						href={githubUrl}
						className="hidden size-8 items-center justify-center rounded-md text-[#8a8f98] transition-colors hover:bg-white/[0.04] hover:text-[#f7f8f8] sm:inline-flex"
						aria-label="Source on GitHub"
					>
						<GithubMark size={16} />
					</a>
					<Link
						to="/docs/$"
						params={{ _splat: 'getting-started' }}
						className="hidden h-8 items-center rounded-md bg-[#f7f8f8] px-3 text-[13px] font-medium text-[#08090a] sm:inline-flex"
					>
						Get started
					</Link>
					<button
						type="button"
						className="inline-flex size-8 items-center justify-center rounded-md text-[#8a8f98] hover:bg-white/[0.04] hover:text-[#f7f8f8] lg:hidden"
						aria-expanded={menuOpen}
						aria-label={menuOpen ? 'Close docs menu' : 'Open docs menu'}
						onClick={() => onMenuOpenChange(!menuOpen)}
					>
						{menuOpen ? <X className="size-4" /> : <Menu className="size-4" />}
					</button>
				</div>
			</nav>
		</header>
	);
}

export function DocsMobileDrawer({
	open,
	onClose,
}: {
	open: boolean;
	onClose: () => void;
}) {
	if (!open) return null;

	return (
		<div className="fixed inset-0 top-16 z-40 lg:hidden">
			<button
				type="button"
				className="absolute inset-0 bg-black/60"
				aria-label="Close docs menu"
				onClick={onClose}
			/>
			<aside className="absolute inset-y-0 left-0 w-72 overflow-y-auto border-r border-white/[0.06] bg-[#08090a]">
				<DocsSidebarNav onNavigate={onClose} />
			</aside>
		</div>
	);
}

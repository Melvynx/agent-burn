import { DocsCopyPage } from '@/components/docs-copy-page.tsx';
import { DocsNeighbours } from '@/components/docs-neighbours.tsx';
import { DocsShell } from '@/components/docs-shell.tsx';
import { DocsTableOfContents, type DocsTocItem } from '@/components/docs-toc.tsx';
import { useMDXComponents } from '@/components/mdx.tsx';
import { cn } from '@/lib/cn.ts';
import { getDocsNeighbours, type DocsNavLink } from '@/lib/docs-nav.ts';
import { docs, source } from '@/lib/source.ts';
import { createServerFn } from '@tanstack/react-start';
import { notFound } from '@tanstack/react-router';
import { Suspense, use } from 'react';
import { encodeMarkdownUrl, gitConfig, siteUrl } from './shared.ts';

export type DocsLoaderData = {
	path: string;
	title: string;
	description: string;
	pageUrl: string;
	markdownUrl: string;
	markdown: string;
	githubUrl: string;
	neighbours: {
		previous: DocsNavLink | null;
		next: DocsNavLink | null;
	};
};

export const loadDocsPage = createServerFn({
	method: 'GET',
})
	.validator((slugs: string[]) => slugs)
	.handler(async ({ data: slugs }) => {
		const page = source.getPage(slugs);
		if (!page) throw notFound();

		const pageUrl = page.url === '/docs/' ? '/docs' : page.url.replace(/\/$/, '');
		const markdown = await page.data.getText('processed');

		return {
			path: page.path,
			title: page.data.title,
			description: page.data.description ?? '',
			pageUrl,
			markdownUrl: encodeMarkdownUrl(page.slugs, page.locale),
			markdown: `# ${page.data.title}\n\n${markdown}`,
			githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/${gitConfig.branch}/docs/content/docs/${page.path}`,
			neighbours: getDocsNeighbours(pageUrl),
		} satisfies DocsLoaderData;
	});

export function docsPageHead(data: DocsLoaderData) {
	return {
		meta: [
			{ title: `${data.title} · Agent Burn` },
			{ name: 'description', content: data.description },
			{ name: 'theme-color', content: '#08090a' },
			{ property: 'og:title', content: `${data.title} · Agent Burn` },
			{ property: 'og:description', content: data.description },
			{ property: 'og:url', content: `${siteUrl}${data.pageUrl}` },
		],
		links: [{ rel: 'canonical', href: `${siteUrl}${data.pageUrl}` }],
	};
}

function Content({ data }: { data: DocsLoaderData }) {
	const page = docs.getPage(data.path);
	if (!page) throw new Error(`unknown page: ${data.path}`);

	const loaded = use(page.load());
	const toc = (loaded.toc ?? []) as DocsTocItem[];
	const MDX = page.body;

	return (
		<div className={cn(toc.length > 0 ? 'xl:pr-64' : '')}>
			<div className="flex w-full">
				<div className="flex min-w-0 flex-1">
					<div className="mx-auto px-6 py-10 sm:py-14">
						<div className="mx-auto flex max-w-prose flex-col gap-8">
							<div className="flex flex-col gap-3">
								<div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
									<h1 className="flex-1 text-[2rem] leading-[1.1] font-medium tracking-[-0.025em] text-balance text-[#f7f8f8] sm:text-4xl">
										{page.title}
									</h1>
									<div className="self-start sm:shrink-0">
										<DocsCopyPage
											markdownUrl={data.markdownUrl}
											pageUrl={`${siteUrl}${data.pageUrl}`}
											markdown={data.markdown}
											githubUrl={data.githubUrl}
										/>
									</div>
								</div>
								{page.description ? (
									<p className="text-lg leading-relaxed text-pretty text-[#8a8f98]">
										{page.description}
									</p>
								) : null}
							</div>

							<div className="docs-prose">
								<MDX components={useMDXComponents()} />
							</div>

							<DocsNeighbours previous={data.neighbours.previous} next={data.neighbours.next} />
						</div>
					</div>
				</div>

				{toc.length > 0 ? (
					<div className="fixed top-16 right-0 hidden h-[calc(100vh-4rem)] overflow-y-auto xl:flex">
						<aside className="w-64 overflow-y-auto border-l border-white/[0.06] bg-[#08090a]">
							<div className="p-6">
								<DocsTableOfContents toc={toc} />
							</div>
						</aside>
					</div>
				) : null}
			</div>
		</div>
	);
}

export function DocsArticle({ data }: { data: DocsLoaderData }) {
	return (
		<DocsShell>
			<Suspense>
				<Content data={data} />
			</Suspense>
		</DocsShell>
	);
}

import { createServerFn } from '@tanstack/react-start';
import { notFound } from '@tanstack/react-router';
import { useFumadocsLoader } from 'fumadocs-core/source/client';
import { DocsLayout } from 'fumadocs-ui/layouts/docs';
import {
	DocsBody,
	DocsDescription,
	DocsPage,
	DocsTitle,
	MarkdownCopyButton,
	ViewOptionsPopover,
} from 'fumadocs-ui/layouts/docs/page';
import { Suspense, use } from 'react';
import { useMDXComponents } from '../components/mdx.tsx';
import { baseOptions } from './layout.shared.tsx';
import { docs, source } from './source.ts';
import { encodeMarkdownUrl, gitConfig } from './shared.ts';

type DocsLoaderData = {
	path: string;
	markdownUrl: string;
	pageTree: Awaited<ReturnType<typeof source.serializePageTree>>;
};

export const loadDocsPage = createServerFn({
	method: 'GET',
})
	.validator((slugs: string[]) => slugs)
	.handler(async ({ data: slugs }) => {
		const page = source.getPage(slugs);
		if (!page) throw notFound();

		return {
			path: page.path,
			markdownUrl: encodeMarkdownUrl(page.slugs, page.locale),
			pageTree: await source.serializePageTree(source.getPageTree()),
		};
	});

function Content({ path, markdownUrl }: { path: string; markdownUrl: string }) {
	const page = docs.getPage(path);
	if (!page) throw new Error(`unknown page: ${path}`);

	const { toc } = use(page.load());
	const MDX = page.body;

	return (
		<DocsPage toc={toc}>
			<DocsTitle>{page.title}</DocsTitle>
			<DocsDescription>{page.description}</DocsDescription>
			<div className="flex flex-row items-center gap-2 border-b -mt-4 pb-6">
				<MarkdownCopyButton markdownUrl={markdownUrl} />
				<ViewOptionsPopover
					markdownUrl={markdownUrl}
					githubUrl={`https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/${gitConfig.branch}/docs/content/docs/${path}`}
				/>
			</div>
			<DocsBody>
				<MDX components={useMDXComponents()} />
			</DocsBody>
		</DocsPage>
	);
}

export function DocsArticle({ data }: { data: DocsLoaderData }) {
	const { path, pageTree, markdownUrl } = useFumadocsLoader(data);

	return (
		<DocsLayout {...baseOptions()} tree={pageTree}>
			<div id="main-content">
				<Suspense>
					<Content path={path} markdownUrl={markdownUrl} />
				</Suspense>
			</div>
		</DocsLayout>
	);
}

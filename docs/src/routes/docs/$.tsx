import { DocsArticle, loadDocsPage } from '@/lib/docs-page.tsx';
import { createFileRoute } from '@tanstack/react-router';
import { docs } from '@/lib/source.ts';

export const Route = createFileRoute('/docs/$')({
	component: Page,
	loader: async ({ params }) => {
		const slugs = params._splat?.split('/').filter(Boolean) ?? [];
		const data = await loadDocsPage({ data: slugs });
		await docs.getPage(data.path)?.preload();
		return data;
	},
});

function Page() {
	return <DocsArticle data={Route.useLoaderData()} />;
}

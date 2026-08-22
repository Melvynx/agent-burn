import { DocsArticle, loadDocsPage } from '@/lib/docs-page.tsx';
import { createFileRoute } from '@tanstack/react-router';
import { docs } from '@/lib/source.ts';

export const Route = createFileRoute('/docs/')({
	component: Page,
	loader: async () => {
		const data = await loadDocsPage({ data: [] });
		await docs.getPage(data.path)?.preload();
		return data;
	},
});

function Page() {
	return <DocsArticle data={Route.useLoaderData()} />;
}

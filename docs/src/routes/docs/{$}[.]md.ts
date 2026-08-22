import { decodeMarkdownUrl } from '@/lib/shared.ts';
import { getLLMText, source } from '@/lib/source.ts';
import { createFileRoute, notFound } from '@tanstack/react-router';

export const Route = createFileRoute('/docs/{$}.md')({
	server: {
		handlers: {
			GET: async ({ params }) => {
				const slugs = decodeMarkdownUrl(params._splat?.split('/') ?? []);
				const page = source.getPage(slugs);
				if (!page) throw notFound();

				return new Response(await getLLMText(page), {
					headers: {
						'Content-Type': 'text/markdown',
					},
				});
			},
		},
	},
});

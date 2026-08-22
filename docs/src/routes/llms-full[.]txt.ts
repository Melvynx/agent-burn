import { getLLMText, source } from '@/lib/source.ts';
import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/llms-full.txt')({
	server: {
		handlers: {
			GET: async () => {
				const scanned = await Promise.all(source.getPages().map(page => getLLMText(page)));
				return new Response(scanned.join('\n\n'));
			},
		},
	},
});

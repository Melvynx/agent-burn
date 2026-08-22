import { baseOptions } from '@/lib/layout.shared.tsx';
import { HomeLayout } from 'fumadocs-ui/layouts/home';
import { DefaultNotFound } from 'fumadocs-ui/layouts/home/not-found';

export function NotFound() {
	return (
		<HomeLayout {...baseOptions()}>
			<DefaultNotFound />
		</HomeLayout>
	);
}

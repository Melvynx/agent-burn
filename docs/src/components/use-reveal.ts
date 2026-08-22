import { useEffect } from 'react';

export function useReveal() {
	useEffect(() => {
		const targets = document.querySelectorAll<HTMLElement>('[data-reveal]');

		if (!('IntersectionObserver' in window)) {
			targets.forEach(element => element.classList.add('is-in'));
			return;
		}

		document.documentElement.classList.add('js-reveal');

		const observer = new IntersectionObserver(
			entries => {
				for (const entry of entries) {
					if (!entry.isIntersecting) continue;
					entry.target.classList.add('is-in');
					observer.unobserve(entry.target);
				}
			},
			{ rootMargin: '0px 0px -10% 0px', threshold: 0.05 },
		);

		targets.forEach(element => observer.observe(element));

		return () => {
			observer.disconnect();
			document.documentElement.classList.remove('js-reveal');
		};
	}, []);
}

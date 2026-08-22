import { Check, Copy } from 'lucide-react';
import { useState } from 'react';

export function CopyLine({ value }: { value: string }) {
	const [copied, setCopied] = useState(false);

	return (
		<button
			type="button"
			className={`copy-line${copied ? ' is-copied' : ''}`}
			onClick={() => {
				void navigator.clipboard?.writeText(value);
				setCopied(true);
				window.setTimeout(() => setCopied(false), 1600);
			}}
		>
			<code>
				<b>$ </b>
				{value}
			</code>
			<span className="copy-line-icons" aria-hidden="true">
				<Copy className="copy-icon-copy" size={14} />
				<Check className="copy-icon-check" size={14} />
			</span>
			<span className="sr-only">{copied ? 'Command copied' : 'Copy install command'}</span>
		</button>
	);
}

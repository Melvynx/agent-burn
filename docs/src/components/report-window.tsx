const days = [
	['08-18', '$9.40', '3.1M', 'Claude 62%', 'Codex 28%', 'Cursor 10%'],
	['08-19', '$14.20', '4.8M', 'Claude 58%', 'Codex 31%', 'Cursor 11%'],
	['08-20', '$12.40', '4.2M', 'Claude 65%', 'Codex 26%', 'Cursor 9%'],
	['08-21', '$18.05', '6.1M', 'Claude 63%', 'Codex 27%', 'Cursor 10%'],
	['08-22', '$16.80', '5.7M', 'Claude 70%', 'Codex 21%', 'Cursor 9%'],
] as const;

const plans = [
	['Claude Max 20x', '$200/mo', '$186', '93%'],
	['Codex Pro', '$200/mo', '$94', '47%'],
	['Cursor Ultra', '$200/mo', '$41', '21%'],
] as const;

export function ReportWindow() {
	return (
		<figure className="window">
			<figcaption className="sr-only">
				A representative Agent Burn terminal report. Five days of local usage with API-equivalent
				cost, then subscription value against Claude, Codex, and Cursor plan prices.
			</figcaption>
			<div className="window-bar" aria-hidden="true">
				<div className="traffic">
					<span />
					<span />
					<span />
				</div>
				<div className="window-title">
					<strong>summary --value</strong>
					<span>agent-burn</span>
				</div>
			</div>
			<div className="app-terminal" aria-hidden="true">
				<p className="t-dim">
					$ npx agent-burn@latest summary --value
				</p>
				<p className="t-space t-head">
					<span>Date</span>
					<span>Cost</span>
					<span>Tokens</span>
					<span>Mix</span>
				</p>
				{days.map(([date, cost, tokens, ...mix]) => (
					<p key={date} className="t-row">
						<span className="t-cyan">{date}</span>
						<span className="t-cost">{cost}</span>
						<span>{tokens}</span>
						<span className="t-dim">{mix.join(' · ')}</span>
					</p>
				))}
				<p className="t-space t-label">Subscription value</p>
				{plans.map(([name, price, used, pct]) => (
					<p key={name} className="t-plan">
						<span>{name}</span>
						<span className="t-dim">{price}</span>
						<span className="t-cost">{used}</span>
						<span className={pct.startsWith('9') ? 't-hot' : 't-live'}>{pct}</span>
					</p>
				))}
				<p className="t-space t-dim">Local logs only. Nothing left the machine.</p>
			</div>
		</figure>
	);
}

import { CopyLine } from '@/components/copy-line.tsx';
import { ReportWindow } from '@/components/report-window.tsx';
import { useReveal } from '@/components/use-reveal.ts';
import { githubUrl, installCommand, npmUrl } from '@/lib/shared.ts';
import { createFileRoute, Link } from '@tanstack/react-router';
import { ArrowUpRight, BookOpen } from 'lucide-react';
import type { ReactNode } from 'react';

export const Route = createFileRoute('/')({
	component: LandingPage,
});

const facts = [
	['Local first', 'Reads Claude, Codex, and Cursor logs on this machine. Nothing is uploaded.'],
	['Two commands', 'summary for the all-up view. harness for one weekly subscription window.'],
	['API-equivalent $', '--value compares local token spend to the monthly plan you actually pay.'],
	['JSON when you need it', '--json and --jq for scripts. The terminal table stays the default.'],
] as const;

const capabilities = [
	{
		title: 'Summary',
		body: 'Aggregate detected local usage, daily cost, token volume, and optional subscription value in one table.',
		detail: 'agent-burn summary --value',
	},
	{
		title: 'Harness',
		body: 'Focus Claude Code or Codex on the current weekly limit, reset timing, and a trailing-30-day spend mix.',
		detail: 'agent-burn harness claude --value',
	},
	{
		title: 'Plan overrides',
		body: 'Auto-detect when the local snapshot has a plan. Override with a named tier or a raw monthly price.',
		detail: '--claude-plan max-20x',
	},
	{
		title: 'Offline pricing',
		body: 'Embedded LiteLLM prices cover a fully local run. Skip live dashboard calls when you want a sealed report.',
		detail: '--offline',
	},
	{
		title: 'Charts and HTML',
		body: 'Stack daily spend by model in the terminal, or write an interactive HTML report and open it.',
		detail: 'summary --chart --html',
	},
	{
		title: 'Config files',
		body: 'Keep timezone, cost mode, and offline defaults in JSON. CLI flags still win.',
		detail: '--config ./agent-burn.json',
	},
] as const;

function LandingPage() {
	useReveal();

	return (
		<div className="landing">
			<SiteHeader />
			<main id="main-content">
				<section className="hero">
					<div className="hero-copy">
						<Link to="/docs/$" params={{ _splat: 'installation' }} className="tag">
							npx · pnpm dlx · bunx · nix
							<ArrowUpRight size={12} />
						</Link>
						<h1>You already burned the tokens.</h1>
						<p className="lede">
							Agent Burn reads local Claude Code, Codex, and Cursor usage and answers one question:
							is the subscription paying for itself?
						</p>
						<div className="actions">
							<Link to="/docs/$" params={{ _splat: 'getting-started' }} className="btn btn-primary">
								<BookOpen size={16} />
								Read the docs
							</Link>
							<a className="btn btn-ghost" href={githubUrl}>
								Source
							</a>
						</div>
						<CopyLine value={installCommand} />
					</div>
					<div className="hero-stage">
						<ReportWindow />
					</div>
				</section>

				<ul className="facts">
					{facts.map(([title, body], index) => (
						<li key={title} data-reveal style={{ '--i': index } as never}>
							<strong>{title}</strong>
							<span>{body}</span>
						</li>
					))}
				</ul>

				<Section
					id="cost"
					kicker="The bill"
					title="The weekly limit is not the price."
					lede="Dashboards tell you that you hit a cap. They do not tell you what those tokens would have cost at API rates, which day did the damage, or whether Max is cheaper than the usage you already ran."
				>
					<div className="compare" data-reveal>
						<article>
							<p className="kicker">What you see</p>
							<h3>Limit reached</h3>
							<p>A reset countdown. A vague “you are using the plan.” No model mix, no daily cost.</p>
						</article>
						<article>
							<p className="kicker">What local logs have</p>
							<h3>$186 of $200</h3>
							<p>
								API-equivalent spend by day, by model, by agent. Enough to decide if the plan is
								earning its keep.
							</p>
						</article>
					</div>
				</Section>

				<Section
					id="commands"
					kicker="Commands"
					title="summary for the pile. harness for the window."
					lede="The public CLI is two commands. Running agent-burn with no arguments is summary."
				>
					<div className="command-grid">
						<article data-reveal>
							<p className="kicker">All-up</p>
							<h3>summary</h3>
							<p>
								Detected local usage across Claude, Codex, and Cursor. Quick ranges, explicit
								dates, optional value, chart, and HTML.
							</p>
							<code>agent-burn summary week --value</code>
						</article>
						<article data-reveal style={{ '--i': 1 } as never}>
							<p className="kicker">One subscription</p>
							<h3>harness</h3>
							<p>
								Claude or Codex only. Weekly limit burn, reset timing, and a 30-day split of input,
								output, and cache tokens.
							</p>
							<code>agent-burn harness codex --value</code>
						</article>
					</div>
				</Section>

				<Section
					id="sources"
					kicker="Sources"
					title="The files are already on disk."
					lede="Claude Code and Codex are the harness targets because they expose a useful weekly limit. Cursor still lands in summary, including charts and HTML."
				>
					<ul className="source-list">
						<li data-reveal>
							<strong>Claude Code</strong>
							<span>~/.claude and ~/.config/claude/projects</span>
						</li>
						<li data-reveal style={{ '--i': 1 } as never}>
							<strong>Codex</strong>
							<span>${'{CODEX_HOME:-~/.codex}'}</span>
						</li>
						<li data-reveal style={{ '--i': 2 } as never}>
							<strong>Cursor</strong>
							<span>local state.vscdb, then the signed-in dashboard usage API</span>
						</li>
					</ul>
				</Section>

				<Section
					id="capabilities"
					kicker="Capabilities"
					title="What the CLI actually does."
					lede="No account, no upload, no wrapper bins. The report is local aggregation plus optional live limit data."
				>
					<ul className="specs">
						{capabilities.map((item, index) => (
							<li key={item.title} data-reveal style={{ '--i': index } as never}>
								<h3>{item.title}</h3>
								<p>{item.body}</p>
								<code>{item.detail}</code>
							</li>
						))}
					</ul>
				</Section>

				<section className="section install" id="install" data-reveal>
					<div className="section-head">
						<div>
							<p className="kicker">Install</p>
							<h2>One line, then the report.</h2>
							<p className="lede">
								The npm package also installs <code>burn</code> as a short alias. Nix and package
								runners are documented in the install guide.
							</p>
						</div>
						<div className="actions">
							<Link to="/docs/$" params={{ _splat: 'installation' }} className="btn btn-primary">
								Installation
							</Link>
							<a className="btn btn-ghost" href={npmUrl}>
								npm
							</a>
						</div>
					</div>
					<pre className="install-shell">
						<span style={{ '--i': 0 } as never}>$ {installCommand}</span>
						<span className="t-dim" style={{ '--i': 1 } as never}>
							{'\n'}
							{'\n'}✓ local logs read
						</span>
						<span className="t-dim" style={{ '--i': 2 } as never}>
							{'\n'}✓ prices resolved
						</span>
						<span className="t-live" style={{ '--i': 3 } as never}>
							{'\n'}✓ subscription value printed
						</span>
					</pre>
				</section>
			</main>
			<SiteFooter />
		</div>
	);
}

function SiteHeader() {
	return (
		<header className="site-header">
			<div className="header-inner">
				<Link to="/" className="brand">
					<img src="/logo.svg" alt="" width={22} height={22} />
					Agent Burn
				</Link>
				<nav aria-label="Main">
					<a href="#cost">Why</a>
					<a href="#commands">Commands</a>
					<a href="#sources">Sources</a>
					<Link to="/docs/$" params={{ _splat: '' }}>
						Docs
					</Link>
				</nav>
				<div className="header-actions">
					<a className="header-source" href={githubUrl} aria-label="Source on GitHub">
						<GithubMark size={16} />
					</a>
					<Link to="/docs/$" params={{ _splat: 'getting-started' }} className="btn btn-small">
						Get started
					</Link>
				</div>
			</div>
		</header>
	);
}

function Section({
	id,
	kicker,
	title,
	lede,
	children,
}: {
	id: string;
	kicker: string;
	title: string;
	lede: string;
	children: ReactNode;
}) {
	return (
		<section className="section" id={id}>
			<div className="section-head" data-reveal>
				<div>
					<p className="kicker">{kicker}</p>
					<h2>{title}</h2>
					<p className="lede">{lede}</p>
				</div>
			</div>
			{children}
		</section>
	);
}

function SiteFooter() {
	return (
		<footer className="site-footer">
			<div className="footer-inner">
				<Link to="/" className="brand">
					<img src="/logo.svg" alt="" width={20} height={20} />
					Agent Burn
				</Link>
				<p>Local subscription value reports.</p>
				<nav aria-label="Footer">
					<Link to="/docs/$" params={{ _splat: '' }}>
						Docs
					</Link>
					<a href={githubUrl}>Source</a>
					<a href={npmUrl}>npm</a>
					<a href={`${githubUrl}/releases`}>Releases</a>
					<a href={`${githubUrl}/blob/main/LICENSE`}>MIT</a>
				</nav>
				<p className="footer-credit">
					Built by <a href="https://melvynx.dev">Melvynx</a>
				</p>
			</div>
		</footer>
	);
}

function GithubMark({ size }: { size: number }) {
	return (
		<svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
			<path d="M12 .3a12 12 0 0 0-3.79 23.4c.6.11.82-.26.82-.58v-2.02c-3.34.73-4.04-1.61-4.04-1.61-.55-1.39-1.33-1.76-1.33-1.76-1.09-.74.08-.73.08-.73 1.2.09 1.84 1.24 1.84 1.24 1.07 1.83 2.81 1.3 3.5 1 .11-.78.42-1.3.76-1.6-2.67-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.12-.3-.54-1.52.12-3.18 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6 0c2.29-1.55 3.3-1.23 3.3-1.23.66 1.66.24 2.88.12 3.18.77.84 1.24 1.91 1.24 3.22 0 4.61-2.81 5.62-5.49 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.22.7.82.58A12 12 0 0 0 12 .3Z" />
		</svg>
	);
}

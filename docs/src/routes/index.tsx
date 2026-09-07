import { CopyLine } from '@/components/copy-line.tsx';
import { GithubMark } from '@/components/logo.tsx';
import { githubUrl, installCommand, npmUrl } from '@/lib/shared.ts';
import { createFileRoute, Link } from '@tanstack/react-router';
import { ArrowDown, ArrowUpRight, Check, Terminal } from 'lucide-react';

export const Route = createFileRoute('/')({ component: LandingPage });
const providers = [
	['codex', 'Codex'],
	['claude', 'Claude'],
	['cursor', 'Cursor'],
	['opencode', 'OpenCode'],
	['gemini', 'Gemini'],
	['pi', 'Pi'],
	['droid', 'Droid'],
	['openclaw', 'OpenClaw'],
	['kimi', 'Kimi'],
] as const satisfies readonly (readonly [string, string])[];
const commands = [
	[
		'The whole picture',
		'See detected agents, token usage and API-equivalent value together.',
		'npx agent-burn@latest summary --value',
	],
	[
		'Your subscription window',
		'Inspect Codex limits, reset timing and subscription value.',
		'npx agent-burn@latest harness codex --value',
	],
	[
		'Claude, in focus',
		'Check Claude usage and the available subscription limits.',
		'npx agent-burn@latest harness claude --value',
	],
	[
		'Ready for your scripts',
		'Get structured data to build your own reports and workflows.',
		'npx agent-burn@latest summary --value --json',
	],
] as const;
function Download({ small = false }: { small?: boolean }) {
	return (
		<a className={`download${small ? ' small' : ''}`} href="/download">
			<ArrowDown size={17} />
			Get the Mac app
		</a>
	);
}
function LandingPage() {
	return (
		<div className="landing">
			<header className="site-header">
				<a href="/" className="brand">
					<img src="/product/icon.png" alt="" width="34" height="34" />
					Agent Burn
				</a>
				<nav aria-label="Main navigation">
					<a href="#app">The app</a>
					<a href="#cli">The CLI</a>
					<Link to="/docs/$" params={{ _splat: '' }}>
						Docs
					</Link>
					<a href={githubUrl} aria-label="Agent Burn on GitHub">
						<GithubMark size={20} />
					</a>
				</nav>
				<Download small />
			</header>
			<main id="main-content">
				<section className="hero">
					<a className="release-note" href={`${githubUrl}/releases`}>
						<span />
						Meet Agent Burn for macOS <ArrowUpRight size={14} />
					</a>
					<h1>
						Keep an eye on
						<br />
						your <span>agent burn.</span>
					</h1>
					<p className="hero-description">
						Your agents are working hard. See what they spend,
						<br className="desktop-break" /> how much is left, and when to slow
						down.
					</p>
					<div className="hero-actions">
						<Download />
						<a className="secondary-link" href="#cli">
							<Terminal size={17} />
							Prefer the terminal?
						</a>
					</div>
					<p className="compatibility">
						Free & open source · macOS 14+ · Apple Silicon & Intel
					</p>
					<div className="product-stage" id="app">
						<div className="stage-note">
							<span className="status-dot" />
							Your entire agent stack. One native Mac app.
						</div>
						<div className="mac-window">
							<div className="mac-title">
								<span className="traffic">
									<i />
									<i />
									<i />
								</span>
								<span>Agent Burn</span>
								<span>General · Codex · Claude · Cursor</span>
							</div>
							<img
								src="/product/dashboard.png"
								alt="Agent Burn dashboard showing spend, tokens, daily usage and a breakdown across coding agents"
								width="2120"
								height="1560"
								fetchPriority="high"
							/>
						</div>
						<div className="stage-caption">
							<span>Native SwiftUI. Powered by the Agent Burn CLI.</span>
							<span>Product captures show example usage.</span>
						</div>
					</div>
				</section>
				<section className="providers" aria-label="Supported agents">
					<p>Bring your favorite agents.</p>
					<div>
						{providers.map(([id, name]) => (
							<span key={id}>
								<img
									src={`/brands/${id}.png`}
									alt=""
									width="25"
									height="25"
									loading="lazy"
								/>
								{name}
							</span>
						))}
					</div>
					<a href="/docs">
						Explore data sources <ArrowUpRight size={14} />
					</a>
				</section>
				<section className="feature-split" id="limits">
					<div className="feature-copy">
						<span className="section-number">01 / In your menu bar</span>
						<h2>
							A little glance.
							<br />A lot of clarity.
						</h2>
						<p>
							Check your remaining quota without leaving your work. Switch
							between agents, follow your burn rate, and see when your limits
							reset.
						</p>
						<ul>
							<li>
								<Check />
								Remaining quota and reset times
							</li>
							<li>
								<Check />
								Actual usage and projected pace
							</li>
							<li>
								<Check />
								One click to the full dashboard
							</li>
						</ul>
						<p className="fine-print">
							Limits and forecasts depend on the data each provider exposes.
						</p>
					</div>
					<figure className="popup-stage">
						<div className="mini-menubar">
							<span>Agent Burn</span>
							<span>◉ &nbsp; 64% &nbsp; ◷</span>
						</div>
						<img
							src="/product/menu-bar.png"
							alt="Agent Burn menu-bar popover with Codex remaining quota and a burn-rate forecast chart"
							width="880"
							height="1560"
							loading="lazy"
						/>
					</figure>
				</section>
				<section className="history-section">
					<div className="history-heading">
						<span className="section-number">02 / The bigger picture</span>
						<h2>
							Your logs may disappear.
							<br />
							Your history shouldn't.
						</h2>
						<p>
							Agent Burn preserves daily spend and token totals on your Mac.
							Look back across weeks, months and all recorded time, even after
							old source logs are removed.
						</p>
					</div>
					<div className="history-details">
						<div>
							<strong>Only the metrics</strong>
							<p>
								Daily totals, not your conversations or prompts. A small local
								archive that you can back up yourself.
							</p>
						</div>
						<div>
							<strong>Every agent, together</strong>
							<p>
								Compare providers in General, or explore models, tokens and
								available plan information in each agent's tab.
							</p>
						</div>
						<div>
							<strong>Your data stays yours</strong>
							<p>
								No Agent Burn account or analytics service. Live mode can
								contact your providers and pricing sources to retrieve usage.
							</p>
						</div>
					</div>
				</section>
				<section className="cursor-section">
					<div>
						<span className="section-number">03 / Beyond a single number</span>
						<h2>
							Follow the spend.
							<br />
							Understand the value.
						</h2>
						<p>
							Compare API-equivalent usage with your subscription price. Explore
							the models behind your totals and, where available, included
							allowance and promotional credits.
						</p>
						<p className="fine-print">
							API-equivalent spend estimates token value. It is not your
							invoice. Available detail varies by provider and retained history.
						</p>
					</div>
					<figure>
						<img
							src="/product/cursor.png"
							alt="Cursor tab in Agent Burn with spend, tokens, a daily chart and per-model usage"
							width="2120"
							height="1560"
							loading="lazy"
						/>
					</figure>
				</section>
				<section className="cli-section" id="cli">
					<div className="cli-heading">
						<span className="section-number">
							04 / At home in your terminal
						</span>
						<h2>
							Same engine.
							<br />
							Your kind of interface.
						</h2>
						<p>
							The Rust CLI runs on macOS, Linux and Windows. Run it with npx, or
							install it once with npm.
						</p>
					</div>
					<div className="terminal-install">
						<div className="terminal-top">
							<Terminal size={17} />
							<span>Start with a single command</span>
							<span>Node.js 22+</span>
						</div>
						<CopyLine value={installCommand} />
						<p>No configuration needed for supported local logs.</p>
					</div>
					<div className="command-list">
						{commands.map(([title, body, command]) => (
							<div key={title}>
								<div>
									<h3>{title}</h3>
									<p>{body}</p>
								</div>
								<CopyLine value={command} />
							</div>
						))}
					</div>
					<div className="cli-links">
						<Link to="/docs/$" params={{ _splat: 'installation' }}>
							Installation guide <ArrowUpRight size={15} />
						</Link>
						<a href={npmUrl}>
							View on npm <ArrowUpRight size={15} />
						</a>
					</div>
				</section>
				<section className="open-section" id="open-source">
					<img
						src="/product/icon.png"
						alt="Agent Burn flame and terminal icon"
						width="88"
						height="88"
						loading="lazy"
					/>
					<h2>Small app. Open book.</h2>
					<p>
						Free to use. MIT licensed. Read the source, build it yourself,
						<br className="desktop-break" /> or help make agent usage a little
						easier to understand.
					</p>
					<div className="hero-actions">
						<Download />
						<a
							className="secondary-link"
							href={`${githubUrl}/tree/codex/macos-product-release`}
						>
							<GithubMark size={18} />
							Explore the source
						</a>
					</div>
					<p className="compatibility">
						Developer ID signed. Public download pending Apple notarization.
					</p>
				</section>
				<section className="faq">
					<h2>A few things to know.</h2>
					{[
						[
							'How do I install the Mac app?',
							'Download the ZIP, unzip it, and move Agent Burn to Applications. Open it to access the dashboard and menu-bar view. The app includes the CLI; Node.js is not required for the Mac app.',
						],
						[
							'Does it update automatically?',
							'The app checks for signed updates automatically. You can disable checks in Settings or choose Check for Updates from the Agent Burn menu. Sparkle guides you through installing an available update.',
						],
						[
							'Is the spend shown my actual bill?',
							'No. API-equivalent value estimates what your token usage would cost at model API prices. Your subscription charge, allowance and credits are shown separately when available.',
						],
						[
							'Can I recover every old session?',
							'Only data that still exists in logs or provider responses can be recovered. Once observed, daily totals are retained locally without expiration. Back up the metrics file to protect it if you lose your Mac.',
						],
					].map(([question, answer]) => (
						<details key={question}>
							<summary>
								{question}
								<span>+</span>
							</summary>
							<p>{answer}</p>
						</details>
					))}
				</section>
			</main>
			<footer className="site-footer">
				<a className="brand" href="/">
					<img src="/product/icon.png" alt="" width="28" height="28" />
					Agent Burn
				</a>
				<span>
					Made by <a href="https://melvynx.dev">Melvyn</a>
				</span>
				<nav aria-label="Footer">
					<a href={githubUrl}>GitHub</a>
					<a href="/docs">Documentation</a>
					<a href={`${githubUrl}/releases`}>Releases</a>
					<a href={`${githubUrl}/blob/main/LICENSE`}>MIT license</a>
				</nav>
			</footer>
		</div>
	);
}

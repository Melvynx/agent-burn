#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import {
	chmodSync,
	cpSync,
	existsSync,
	mkdtempSync,
	mkdirSync,
	readFileSync,
	writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const nativePackages = {
	darwin: {
		arm64: 'agent-burn-darwin-arm64',
		x64: 'agent-burn-darwin-x64',
	},
	linux: {
		arm64: 'agent-burn-linux-arm64',
		x64: 'agent-burn-linux-x64',
	},
	win32: {
		arm64: 'agent-burn-win32-arm64',
		x64: 'agent-burn-win32-x64',
	},
};

const options = parseArgs(process.argv.slice(2));
const platform = process.platform;
const arch = process.arch;
const nativePackageName = nativePackages[platform]?.[arch];

if (nativePackageName == null) {
	fail(`Unsupported release target: ${platform}-${arch}`);
}

const binaryName = platform === 'win32' ? 'agent-burn.exe' : 'agent-burn';
const rootPackagePath = join(repoRoot, 'package.json');
const wrapperDir = join(repoRoot, 'apps', 'agent-burn');
const wrapperPackagePath = join(wrapperDir, 'package.json');
const nativeDir = join(repoRoot, 'packages', nativePackageName);
let wrapperPackageJson = readPackageJson(wrapperPackagePath);
let nativePackageJson = readPackageJson(join(nativeDir, 'package.json'));
let version = wrapperPackageJson.version;

if (options.bump != null) {
	if (!options.allowDirty) {
		ensureCleanTrackedWorktree();
	}
	const nextVersion = resolveNextVersion(version, options.bump);
	log(`Bumping ${version} -> ${nextVersion}`);
	updateReleaseVersions(nextVersion);
	wrapperPackageJson = readPackageJson(wrapperPackagePath);
	nativePackageJson = readPackageJson(join(nativeDir, 'package.json'));
	version = nextVersion;
} else if (!options.allowDirty) {
	ensureCleanTrackedWorktree();
}

if (nativePackageJson.version !== version) {
	fail(`${nativePackageName} is ${nativePackageJson.version}, expected ${version}`);
}

log(`Release target: agent-burn@${version} + ${nativePackageName}@${version}`);

if (!options.dryRun && !options.skipAuthCheck) {
	run('npm', ['whoami', ...registryArgs()], { capture: true });
}

if (!options.skipExistingCheck) {
	ensurePackageVersionIsFree(nativePackageName, version);
	ensurePackageVersionIsFree('agent-burn', version);
}

run('cargo', [
	'build',
	'--manifest-path',
	join(repoRoot, 'rust', 'Cargo.toml'),
	'--release',
	'--bin',
	'agent-burn',
]);

const builtBinary = join(repoRoot, 'rust', 'target', 'release', binaryName);
const nativeBinary = join(nativeDir, 'bin', binaryName);

if (!existsSync(builtBinary)) {
	fail(`Cargo did not create ${builtBinary}`);
}

mkdirSync(dirname(nativeBinary), { recursive: true });
cpSync(builtBinary, nativeBinary);
if (platform !== 'win32') {
	chmodSync(nativeBinary, 0o755);
}

const versionOutput = run(nativeBinary, ['--version'], { capture: true }).stdout.trim();
if (!versionOutput.endsWith(` ${version}`)) {
	fail(`${nativeBinary} reports "${versionOutput}", expected version ${version}`);
}

runNativeSmoke(nativeBinary);

run('pnpm', ['--dir', nativeDir, 'exec', 'publint']);
run('pnpm', ['--dir', wrapperDir, 'exec', 'publint']);

const packDir = mkdtempSync(join(tmpdir(), 'agent-burn-release-'));
packPackage(nativeDir, packDir);
packPackage(wrapperDir, packDir);

const nativeTarball = join(packDir, `${nativePackageName}-${version}.tgz`);
const wrapperTarball = join(packDir, `agent-burn-${version}.tgz`);

for (const tarball of [nativeTarball, wrapperTarball]) {
	if (!existsSync(tarball)) {
		fail(`Expected tarball was not created: ${tarball}`);
	}
}

publishTarball(nativeTarball);
publishTarball(wrapperTarball);

if (!options.dryRun) {
	run('npm', ['view', `agent-burn@${version}`, 'version', ...registryArgs()], {
		capture: true,
	});
	log(`Published agent-burn@${version}`);
	commitReleaseIfRequested(version);
	log('Verify with: npm install -g agent-burn && agent-burn --version');
} else {
	log('Dry run complete. No package was published.');
}

function parseArgs(args) {
	const parsed = {
		access: 'public',
		allowDirty: false,
		bump: undefined,
		commit: false,
		dryRun: false,
		otp: undefined,
		provenance: false,
		registry: undefined,
		skipAuthCheck: false,
		skipExistingCheck: false,
		tag: 'latest',
		push: false,
	};

	for (let index = 0; index < args.length; index += 1) {
		const arg = args[index];
		if (arg === '--') {
			continue;
		} else if (arg === '--allow-dirty') {
			parsed.allowDirty = true;
		} else if (arg === '--dry-run') {
			parsed.dryRun = true;
		} else if (arg === '--commit') {
			parsed.commit = true;
		} else if (arg === '--push') {
			parsed.commit = true;
			parsed.push = true;
		} else if (arg === '--skip-auth-check') {
			parsed.skipAuthCheck = true;
		} else if (arg === '--skip-existing-check') {
			parsed.skipExistingCheck = true;
		} else if (arg === '--provenance') {
			parsed.provenance = true;
		} else if (
			arg === '--bump'
			|| arg === '--otp'
			|| arg === '--tag'
			|| arg === '--registry'
			|| arg === '--access'
		) {
			const value = args[index + 1];
			if (value == null || value.startsWith('--')) {
				fail(`${arg} requires a value`);
			}
			index += 1;
			assignOption(parsed, arg, value);
		} else if (arg.startsWith('--bump=')) {
			parsed.bump = arg.slice('--bump='.length);
		} else if (arg.startsWith('--otp=')) {
			parsed.otp = arg.slice('--otp='.length);
		} else if (arg.startsWith('--tag=')) {
			parsed.tag = arg.slice('--tag='.length);
		} else if (arg.startsWith('--registry=')) {
			parsed.registry = arg.slice('--registry='.length);
		} else if (arg.startsWith('--access=')) {
			parsed.access = arg.slice('--access='.length);
		} else {
			fail(`Unknown option: ${arg}`);
		}
	}

	return parsed;
}

function assignOption(parsed, arg, value) {
	if (arg === '--bump') {
		parsed.bump = value;
	} else if (arg === '--otp') {
		parsed.otp = value;
	} else if (arg === '--tag') {
		parsed.tag = value;
	} else if (arg === '--registry') {
		parsed.registry = value;
	} else if (arg === '--access') {
		parsed.access = value;
	}
}

function resolveNextVersion(current, bump) {
	if (/^\d+\.\d+\.\d+$/.test(bump)) {
		return bump;
	}

	const match = /^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$/.exec(current);
	if (match?.groups == null) {
		fail(`Cannot bump non-standard version: ${current}`);
	}

	const major = Number(match.groups.major);
	const minor = Number(match.groups.minor);
	const patch = Number(match.groups.patch);

	if (bump === 'major') {
		return `${major + 1}.0.0`;
	}
	if (bump === 'minor') {
		return `${major}.${minor + 1}.0`;
	}
	if (bump === 'patch') {
		return `${major}.${minor}.${patch + 1}`;
	}

	fail(`Unsupported bump "${bump}". Use patch, minor, major, or an exact x.y.z version.`);
}

function updateReleaseVersions(nextVersion) {
	const packageJsonPaths = [
		rootPackagePath,
		wrapperPackagePath,
		join(repoRoot, 'docs', 'package.json'),
		...Object.values(nativePackages)
			.flatMap((packagesForPlatform) => Object.values(packagesForPlatform))
			.map((packageName) => join(repoRoot, 'packages', packageName, 'package.json')),
	];
	const cargoTomlPaths = [
		join(repoRoot, 'rust', 'crates', 'agent-burn', 'Cargo.toml'),
		join(repoRoot, 'rust', 'crates', 'agent-burn-cli', 'Cargo.toml'),
		join(repoRoot, 'rust', 'crates', 'agent-burn-terminal', 'Cargo.toml'),
		join(repoRoot, 'rust', 'crates', 'agent-burn-test-support', 'Cargo.toml'),
	];

	for (const filePath of packageJsonPaths) {
		const packageJson = readPackageJson(filePath);
		packageJson.version = nextVersion;
		writeFileSync(filePath, `${JSON.stringify(packageJson, null, '\t')}\n`);
	}

	for (const filePath of cargoTomlPaths) {
		const content = readFileSync(filePath, 'utf8');
		const updated = content.replace(/^version = "[^"]+"/m, `version = "${nextVersion}"`);
		if (updated === content) {
			fail(`Could not update package version in ${filePath}`);
		}
		writeFileSync(filePath, updated);
	}
}

function ensureCleanTrackedWorktree() {
	const status = run('git', ['status', '--short', '--untracked-files=no'], { capture: true });
	if (status.stdout.trim() !== '') {
		fail(
			[
				'Working tree has tracked changes:',
				status.stdout.trimEnd(),
				'',
				'Commit or stash them before release, or pass --allow-dirty to publish this exact local tree.',
			].join('\n'),
		);
	}
}

function ensurePackageVersionIsFree(name, packageVersion) {
	const result = run(
		'npm',
		['view', `${name}@${packageVersion}`, 'version', '--json', ...registryArgs()],
		{ allowFailure: true, capture: true },
	);

	if (result.status === 0) {
		fail(`${name}@${packageVersion} already exists on npm. Bump versions before release.`);
	}

	const combinedOutput = `${result.stdout}\n${result.stderr}`;
	if (!combinedOutput.includes('E404')) {
		fail(`Could not confirm npm availability for ${name}@${packageVersion}:\n${combinedOutput}`);
	}
}

function runNativeSmoke(binaryPath) {
	run(binaryPath, ['--help'], { capture: true });
	run(binaryPath, ['summary', '--json'], { capture: true });
	const legacy = run(binaryPath, ['daily'], { allowFailure: true, capture: true });
	if (legacy.status === 0) {
		fail('Legacy command unexpectedly succeeded: agent-burn daily');
	}
}

function packPackage(packageDir, destination) {
	run('pnpm', [
		'--config.ignore-scripts=true',
		'--dir',
		packageDir,
		'pack',
		'--pack-destination',
		destination,
	]);
}

function publishTarball(tarball) {
	const args = [
		'publish',
		tarball,
		'--access',
		options.access,
		'--tag',
		options.tag,
		...registryArgs(),
	];
	if (options.otp != null) {
		args.push('--otp', options.otp);
	}
	if (options.provenance) {
		args.push('--provenance');
	}
	if (options.dryRun) {
		args.push('--dry-run');
	}
	run('npm', args);
}

function commitReleaseIfRequested(releaseVersion) {
	if (!options.commit) {
		return;
	}

	if (options.allowDirty) {
		fail('--commit/--push cannot be combined with --allow-dirty. Commit or stash unrelated changes first.');
	}

	const releaseFiles = [
		'package.json',
		'apps/agent-burn/package.json',
		'docs/package.json',
		'rust/Cargo.lock',
		...Object.values(nativePackages)
			.flatMap((packagesForPlatform) => Object.values(packagesForPlatform))
			.map((packageName) => `packages/${packageName}/package.json`),
		...[
			'agent-burn',
			'agent-burn-cli',
			'agent-burn-terminal',
			'agent-burn-test-support',
		].map((crateName) => `rust/crates/${crateName}/Cargo.toml`),
	];

	run('git', ['add', '--', ...releaseFiles]);
	const staged = run('git', ['diff', '--cached', '--quiet'], {
		allowFailure: true,
		capture: true,
	});
	if (staged.status === 0) {
		log('No release version changes to commit.');
	} else {
		run('git', ['commit', '-m', `chore: release agent-burn v${releaseVersion}`]);
	}

	if (options.push) {
		const branch = run('git', ['branch', '--show-current'], { capture: true }).stdout.trim();
		if (branch === '') {
			fail('Cannot push release commit because the current HEAD is detached.');
		}
		run('git', ['push', 'origin', branch]);
	}
}

function registryArgs() {
	return options.registry == null ? [] : ['--registry', options.registry];
}

function readPackageJson(path) {
	return JSON.parse(readFileSync(path, 'utf8'));
}

function run(command, args, config = {}) {
	const result = spawnSync(command, args, {
		cwd: repoRoot,
		encoding: 'utf8',
		env: {
			...process.env,
			PATH: [
				join(repoRoot, 'node_modules', '.bin'),
				process.env.PATH ?? '',
			].join(':'),
		},
		stdio: config.capture ? 'pipe' : 'inherit',
	});

	if (result.error != null) {
		fail(`${command} failed to start: ${result.error.message}`);
	}

	if (!config.allowFailure && result.status !== 0) {
		const output = config.capture ? `\n${result.stdout ?? ''}${result.stderr ?? ''}` : '';
		fail(`${command} ${args.join(' ')} failed with exit code ${result.status}${output}`);
	}

	return result;
}

function log(message) {
	process.stdout.write(`[release:npm] ${message}\n`);
}

function fail(message) {
	process.stderr.write(`[release:npm] ${message}\n`);
	process.exit(1);
}

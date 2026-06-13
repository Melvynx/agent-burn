import assert from 'node:assert/strict';
import { describe, it, mock } from 'node:test';
import {
	ensureNativeBinaryExecutable,
	isMainModule,
	resolveCliRuntime,
	resolveNativeBinary,
} from './cli.js';

void describe(resolveCliRuntime.name, () => {
	void it('resolves the native package binary for the current supported platform', () => {
		const actual = resolveNativeBinary({
			arch: 'arm64',
			platform: 'darwin',
			resolvePath: (id) => {
				assert.equal(id, 'agent-burn-darwin-arm64/bin/agent-burn');
				return '/native/bin/agent-burn';
			},
		});

		assert.equal(actual, '/native/bin/agent-burn');
	});

	void it('resolves the Windows native package binary with the exe suffix', () => {
		const actual = resolveNativeBinary({
			arch: 'arm64',
			platform: 'win32',
			resolvePath: (id) => {
				assert.equal(id, 'agent-burn-win32-arm64/bin/agent-burn.exe');
				return 'C:\\native\\bin\\agent-burn.exe';
			},
		});

		assert.equal(actual, 'C:\\native\\bin\\agent-burn.exe');
	});

	void it('prefers the matching native package binary when it is available', () => {
		assert.deepEqual(
			resolveCliRuntime({
				argv: ['summary'],
				nativeBinaryPath: '/app/node_modules/agent-burn-darwin-arm64/bin/agent-burn',
			}),
			{
				args: ['summary'],
				command: '/app/node_modules/agent-burn-darwin-arm64/bin/agent-burn',
			},
		);
	});

	void it('fails when the native package binary is unavailable', () => {
		assert.deepEqual(
			resolveCliRuntime({
				arch: 'arm64',
				argv: ['summary'],
				nativeBinaryPath: null,
				platform: 'darwin',
			}),
			{
				errorMessage:
					'agent-burn native binary is not available for darwin-arm64. Reinstall agent-burn so optional native dependencies are installed.\n',
			},
		);
	});

	void it('repairs a native binary that was extracted without executable bits', () => {
		const chmodPath = mock.fn();

		assert.equal(
			ensureNativeBinaryExecutable({
				binaryPath: '/native/bin/agent-burn',
				chmodPath,
				platform: 'linux',
				statPath: () => ({ mode: 0o644 }),
			}),
			undefined,
		);
		assert.deepEqual(
			chmodPath.mock.calls.map((call) => call.arguments),
			[['/native/bin/agent-burn', 0o755]],
		);
	});

	void it('does not chmod an already executable native binary', () => {
		const chmodPath = mock.fn();

		assert.equal(
			ensureNativeBinaryExecutable({
				binaryPath: '/native/bin/agent-burn',
				chmodPath,
				platform: 'darwin',
				statPath: () => ({ mode: 0o755 }),
			}),
			undefined,
		);
		assert.equal(chmodPath.mock.callCount(), 0);
	});

	void it('does not chmod Windows native binaries', () => {
		const chmodPath = mock.fn();

		assert.equal(
			ensureNativeBinaryExecutable({
				binaryPath: 'C:\\native\\bin\\agent-burn.exe',
				chmodPath,
				platform: 'win32',
				statPath: () => ({ mode: 0o644 }),
			}),
			undefined,
		);
		assert.equal(chmodPath.mock.callCount(), 0);
	});

	void it('treats package bin symlinks as the main module entry point', () => {
		const actual = isMainModule({
			argvEntry: '/project/node_modules/.bin/agent-burn',
			moduleUrl: 'file:///project/node_modules/agent-burn/src/cli.js',
			realpathPath: (path) =>
				path === '/project/node_modules/.bin/agent-burn'
					? '/project/node_modules/agent-burn/src/cli.js'
					: path,
		});

		assert.equal(actual, true);
	});
});

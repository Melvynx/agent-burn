# Distribution-only Linux build, kept separate from the default `agent-burn`
# package on purpose:
#
#   * `agent-burn` (package.nix) is the host-native build used for `nix run`,
#     the dev shell, `nix flake check`, and schema generation. On Linux it is
#     glibc-dynamic with a runpath into `/nix/store`, so it is fast for local
#     work but NOT portable to end-user machines.
#   * `agent-burn-static` (this file) cross-compiles to musl and links fully
#     statically, producing the portable binary that `release.yaml` ships to
#     npm. The release matrix runs `nix build .#agent-burn-static` for Linux;
#     macOS arm64 uses the native Nix build, while macOS x64 and Windows fall
#     back to `cargo build` because Nix cannot target those runners.
#
# So Linux release artifacts must come from `.#agent-burn-static`, never the
# default `.#agent-burn`, which would embed unusable `/nix/store` paths.
{
  inputs,
  ...
}:
let
  root = ./..;
in
{
  perSystem =
    {
      config,
      system,
      ...
    }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.rust-overlay.overlays.default ];
      };
    in
    pkgs.lib.mkIf pkgs.stdenv.isLinux {
      packages."agent-burn-static" =
        let
          linuxStaticTarget =
            if system == "x86_64-linux" then "x86_64-unknown-linux-musl" else "aarch64-unknown-linux-musl";
          staticPkgs =
            if system == "x86_64-linux" then
              pkgs.pkgsCross.musl64
            else
              pkgs.pkgsCross.aarch64-multiplatform-musl;
          staticCraneLib = (inputs.crane.mkLib staticPkgs).overrideToolchain (
            p:
            (p.rust-bin.fromRustupToolchainFile (root + /rust-toolchain.toml)).override {
              targets = [ linuxStaticTarget ];
            }
          );
          staticCommonArgs = config.packages.agent-burn.passthru.commonArgs // {
            cargoExtraArgs = "-p agent-burn --bin agent-burn --target ${linuxStaticTarget}";
            nativeBuildInputs = with staticPkgs; [
              mold
              pkg-config
            ];
            buildInputs = [ ];
          };
          # Share the same deps-only cache key, then add static target settings.
          staticDepsOnlyArgs = config.packages.agent-burn.passthru.depsOnlyArgs // {
            cargoExtraArgs = "-p agent-burn --bin agent-burn --target ${linuxStaticTarget}";
            nativeBuildInputs = with staticPkgs; [
              mold
              pkg-config
            ];
            buildInputs = [ ];
          };
          staticCargoArtifacts = staticCraneLib.buildDepsOnly staticDepsOnlyArgs;
        in
        staticCraneLib.buildPackage (
          staticCommonArgs
          // {
            cargoArtifacts = staticCargoArtifacts;
            # Exposed so CI can pin the deps-only artifacts with a Nix profile
            # root and keep them on the sticky disk across runs; otherwise the
            # store path is unreferenced once the binary is built and the disk's
            # GC-root-respecting trim drops it, forcing a full dependency rebuild.
            passthru = {
              cargoArtifacts = staticCargoArtifacts;
            };
            # A PT_INTERP header means the binary requests a dynamic loader,
            # so it would not run on end-user machines without the build-time
            # loader path. READELF is exported by the cross bintools wrapper.
            postInstall = ''
              if "''${READELF:-readelf}" -l $out/bin/agent-burn | grep -q INTERP; then
                echo "error: agent-burn-static is not statically linked" >&2
                exit 1
              fi
            '';
            meta = config.packages.agent-burn.meta // {
              description = "Static Linux build of agent-burn";
            };
          }
        );
    };
}

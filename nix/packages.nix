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
      system,
      ...
    }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.rust-overlay.overlays.default ];
      };
      rustToolchain = pkgs.rust-bin.fromRustupToolchainFile (root + /rust-toolchain.toml);
      craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustToolchain;
      agentBurn = import ../default.nix {
        inherit
          craneLib
          inputs
          pkgs
          root
          ;
      };
      agentBurnProgram = pkgs.lib.getExe' agentBurn "agent-burn";
      # Regeneration-only output for committed models.dev snapshots;
      # `just gen-models-dev-pricing` builds this and copies them into the source
      # tree. It is not part of the agent-burn build, which embeds the committed files.
      models-dev-pricing = pkgs.callPackage ../nix/models-dev-pricing.nix {
        modelsDevSrc = inputs.models-dev;
      };
      publint = pkgs.callPackage ../nix/publint.nix { };
    in
    {
      apps = {
        default = {
          type = "app";
          program = agentBurnProgram;
        };
        "agent-burn" = {
          type = "app";
          program = agentBurnProgram;
        };
      };

      packages = {
        default = agentBurn;
        "agent-burn" = agentBurn;
        inherit models-dev-pricing publint;
      };
    };
}

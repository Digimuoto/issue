{
  description = "Linear Issue CLI - Command-line interface for Linear issue management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Copy all nushell source files to the store
        issueSrc = pkgs.stdenv.mkDerivation {
          name = "issue-src";
          src = ./.;
          installPhase = ''
            mkdir -p $out
            cp -r issue.nu lib commands $out/
          '';
        };

        # Create wrapper script
        issue = pkgs.writeShellScriptBin "issue" ''
          exec ${pkgs.nushell}/bin/nu ${issueSrc}/issue "$@"
        '';
      in
      {
        packages = {
          default = issue;
          issue = issue;
        };

        apps = {
          default = {
            type = "app";
            program = "${issue}/bin/issue";
          };
          issue = {
            type = "app";
            program = "${issue}/bin/issue";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.nushell
          ];

          shellHook = ''
            echo "Linear Issue CLI development environment"
            echo "Run: nu issue.nu <command>"
          '';
        };
      }
    );
}

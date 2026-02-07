{
  description = "clever-computer dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, git-hooks }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pre-commit = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          ruff-format = {
            enable = true;
          };
          ruff = {
            enable = true;
          };
          shellcheck = {
            enable = true;
          };
          govet = {
            enable = true;
          };
          gofmt = {
            enable = true;
          };
        };
      };
    in
    {
      checks.${system}.pre-commit = pre-commit;

      devShells.${system}.default = pkgs.mkShell {
        inherit (pre-commit) shellHook;
        packages = [
          pkgs.go
          pkgs.tart
          pkgs.softnet
          pkgs.sshpass
        ];
      };
    };
}

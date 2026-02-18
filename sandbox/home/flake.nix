{
  description = "clever-computer VM user environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."admin" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          {
            home.username = "admin";
            home.homeDirectory = "/Users/admin";
            home.stateVersion = "24.05";

            # Packages (replaces nix profile add)
            home.packages = with pkgs; [
              gh
              socat
              direnv
            ];

            # Git config
            programs.git = {
              enable = true;
              userName = "clever-computer[bot]";
              userEmail = "clever-computer[bot]@users.noreply.github.com";
              extraConfig = {
                credential.helper = "";
                url."https://x-access-token:proxy-managed@github.proxy/".insteadOf = "https://github.proxy/";
                http."https://github.proxy".sslCAInfo = "/usr/local/share/ca-certificates/github-proxy-ca.crt";
              };
            };

            # Zsh config
            programs.zsh = {
              enable = true;

              shellAliases = {
                claude = "claude --dangerously-skip-permissions";
              };

              sessionVariables = {
                GH_HOST = "github.proxy";
                EXAMPLE_ENV = "hello-world";
              };

              envExtra = ''
                export PATH="$HOME/scripts:$HOME/.local/bin:$PATH"
              '';

              initExtra = ''
                eval "$(direnv hook zsh)"
              '';
            };

            programs.home-manager.enable = true;
          }
        ];
      };
    };
}

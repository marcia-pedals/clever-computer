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
              jq
              socat
              direnv
            ];

            # Git config
            programs.git = {
              enable = true;
              settings = {
                user.name = "clever-computer[bot]";
                user.email = "clever-computer[bot]@users.noreply.github.com";
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
              };

              envExtra = ''
                export PATH="$HOME/scripts:$HOME/.local/bin:$PATH"
                [ -f ~/home-config/secrets.env ] && source ~/home-config/secrets.env
              '';

              initContent = ''
                eval "$(direnv hook zsh)"
              '';
            };

            home.activation.claudeOnboarding = home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              [ -f ~/.claude.json ] || echo '{}' > ~/.claude.json
              ${pkgs.jq}/bin/jq '.hasCompletedOnboarding = true | .theme = "light" |.bypassPermissionsModeAccepted = true' ~/.claude.json > /tmp/.claude.json \
                && mv /tmp/.claude.json ~/.claude.json
            '';

            home.activation.claudeSettings = home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              mkdir -p ~/.claude
              [ -f ~/.claude/settings.json ] || echo '{}' > ~/.claude/settings.json
              ${pkgs.jq}/bin/jq '
                .enabledPlugins["clangd-lsp@claude-plugins-official"] = true |
                .enabledPlugins["swift-lsp@claude-plugins-official"] = true |
                .enabledPlugins["typescript-lsp@claude-plugins-official"] = true
              ' ~/.claude/settings.json > /tmp/.claude-settings.json \
                && mv /tmp/.claude-settings.json ~/.claude/settings.json
            '';

            programs.home-manager.enable = true;
          }
        ];
      };
    };
}

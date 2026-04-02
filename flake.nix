{
  description = "Yudots Revamped dotfiles packaged for NixOS and Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { ... }: {
    nixosModules.default = import ./nix/modules/nixos.nix;
    homeModules.default = import ./nix/modules/home-manager.nix;
  };
}
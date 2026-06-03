{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };
  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        zig
        zls        
        lldb
        # X11
        
        xorg.libX11
        xorg.libXrandr
        # Wayland bullshit
        wayland
        wayland-protocols
        wayland-scanner
        pkg-config
        libxkbcommon 
      ];
    };
  };
}

{
  description = "jetson ffmpeg";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-24.11";
    jetpack-nixos = {
      url = "github:/saronic-technologies/jetpack-nixos?ref=fix/tianocore";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # jetpack-nixos.url = "github:anduril/jetpack-nixos";
    flake-utils.url  = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, jetpack-nixos, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      with pkgs;
      {
        packages = flake-utils.lib.flattenTree {
          ffmpeg-nvmpi = let
            l4t-multimedia = jetpack-nixos.legacyPackages."${system}".l4t-multimedia;
            cudatoolkit = jetpack-nixos.legacyPackages."${system}".cudaPackages.cudatoolkit;
          in pkgs.stdenv.mkDerivation {
            name = "ffmpeg-nvmpi";
            buildInputs = [ l4t-multimedia ];
            nativeBuildInputs = [ pkgs.cmake ];
            src = ./.;
            cmakeFlags = [
              "-DJETSON_MULTIMEDIA_API_DIR=${l4t-multimedia}"
              "-DJETSON_MULTIMEDIA_LIB_DIR=${l4t-multimedia}/lib"
              "-DCUDA_INCLUDE_DIR=${cudatoolkit}/include"
              "-DCUDA_LIB_DIR=${cudatoolkit}/lib"
              "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
            ];
          };

          jetson-ffmpeg-4 = pkgs.ffmpeg_4-full.overrideAttrs (final: prev: {
            patches = prev.patches ++ [ ./ffmpeg_patches/ffmpeg4.4_nvmpi.patch ];
            configureFlags = prev.configureFlags ++ [ "--enable-debug" "--enable-nvmpi" ];
            buildInputs = prev.buildInputs ++ [ self.packages."${system}".ffmpeg-nvmpi ];
            doCheck = false;
          });
        };
      }
    );
}

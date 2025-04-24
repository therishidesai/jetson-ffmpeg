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
        l4t-multimedia = jetpack-nixos.legacyPackages."${system}".l4t-multimedia;
        # Nvidia's included libv4l has very minimal changes against the upstream
        # version. We need to rebuild it from source to ensure it can find nvidia's
        # v4l plugins in the right location. Nvidia's version has the path hardcoded.
        # See https://nv-tegra.nvidia.com/tegra/v4l2-src/v4l2_libs.git
        l4t-multimedia-v4l = pkgs.libv4l.overrideAttrs ({ nativeBuildInputs ? [ ], patches ? [ ], postPatch ? "", postInstall ? "", ... }: {
          nativeBuildInputs = nativeBuildInputs ++ [ pkgs.dpkg ];
          patches = patches ++ pkgs.lib.singleton (pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/OE4T/meta-tegra/85aa94e16104debdd01a3f61a521b73d86340a9f/recipes-multimedia/libv4l2/libv4l2-minimal/0003-Update-conversion-defaults-to-match-NVIDIA-sources.patch";
            sha256 = "sha256-gzWMilEbxkQfbArkCgFSYs9A06fdciCijYYCCpEiHOc=";
          });

          postInstall = postInstall + ''
              ln -sf ${l4t-multimedia}/lib/libv4l/plugins/nv/libv4l2_nvcuvidvideocodec.so $out/lib/libv4l/plugins/libv4l2_nvcuvidvideocodec.so
              ln -sf ${l4t-multimedia}/lib/libv4l/plugins/nv/libv4l2_nvvideocodec.so $out/lib/libv4l/plugins/libv4l2_nvvideocodec.so
            '';
        });
      in
      with pkgs;
      {
        packages = flake-utils.lib.flattenTree {
          l4t-multimedia-v4l = l4t-multimedia-v4l;

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
            configureFlags = prev.configureFlags ++ [ "--enable-nvmpi" ];
            nativeBuildInputs = prev.nativeBuildInputs ++ [ pkg-config ];
            buildInputs = let
              buildInputsNoV4l = builtins.filter (x: !lib.hasInfix "v4l" x.name) prev.buildInputs;
            in buildInputsNoV4l ++ [ self.packages."${system}".ffmpeg-nvmpi l4t-multimedia-v4l ];
            doCheck = false;
          });
        };
      }
    );
}

{pkgs ? import (builtins.fetchTarball {
  url = "https://github.com/nixos/nixpkgs/archive/e0732437e0790ceb447e4f529be29ae62507262b.tar.gz";
  sha256 = "0zrr9dzqvsyipwp4ckpj3mhlqy4dvm2wn3z19vn0ny15bvq8s4g0";
}) {}}: let

mitm = import ../mitm.nix { inherit pkgs; };

src = pkgs.fetchFromGitHub {
  owner = "pdurbin";
  repo = "maven-hello-world";
  rev = "3c086280546719f539a9dcfff042c6d4432a0b77";
  sha256 = "0m4p0vrsva2zadb0dpvj800dcvj4f65w299jjwb89rrhh2x0191c";
};

networkDeps = import ./hellodeps.nix;

# Script to generate/update hellodeps.nix, may need manual post-processing due
# to differences in build sandbox and script environment
updater = pkgs.writeScript "updater.sh" ''
#!${pkgs.runtimeShell}
set -eo pipefail

# Prepare a working directory
d=$(mktemp -d)
cp -r "${src}/" "$d/src"
cd "$d/src"
chmod -R +w .

cd my-app

dump=$(mktemp)
${mitm.start {
  args = ''-w "$dump" -q'';
  offline = false;
  # cachedDeps = networkDeps; # optional, can be used for faster iteration
}}
# Don't print to stdout, always succeed to get partial network deps results too
${pkgs.maven}/bin/mvn compile -Dmaven.repo.local="$(mktemp -d)" >&2 || true
${mitm.processdump {args = "-q -s \"${mitm.dumpscript}\""; dump="$dump";}} | ${mitm.dumpconv}
'';

hello = pkgs.stdenv.mkDerivation {
  name = "hello";
  inherit src;
  buildPhase = ''
set -eo pipefail

cd my-app

${mitm.start {
  cachedDeps = networkDeps;
  args = "-q";
}}
${pkgs.maven}/bin/mvn compile -Dmaven.repo.local="$(mktemp -d)"
'';
installPhase = ''
# just compiling is good enough for initial test
> "$out"
  '';
};
in {
  inherit updater hello;
  mitmdump = pkgs.mitmproxy;
}

{pkgs, ...}: rec {
  mkTerraformProvider = {
    owner,
    repo,
    version,
    src,
    registry ? null,
  }: let
    inherit (pkgs.go) GOARCH GOOS;
    # if the user doesnt specify a registry, we shouldn't add one in required_providers
    provider-orig-source-address = "${
      if registry != null
      then "${registry}/"
      else ""
    }${owner}/${repo}";
    registry_default =
      if registry == null
      then "registry.opentofu.org"
      else registry;
    provider-source-address = "${registry_default}/${owner}/${repo}";
  in
    pkgs.stdenv.mkDerivation {
      pname = "terraform-provider-${repo}";
      inherit version src;

      unpackPhase = "unzip -o $src";

      nativeBuildInputs = [pkgs.unzip pkgs.patchelf];

      buildPhase = ":";

      # The upstream terraform wrapper assumes the provider filename here.
      installPhase = ''
        dir=$out/libexec/terraform-providers/${provider-source-address}/${version}/${GOOS}_${GOARCH}
        mkdir -p "$dir"
        mv terraform-* "$dir/"

        # Some registry providers ship DYNAMICALLY-LINKED binaries, which NixOS's 
        # stub-ld refuses to run ("Could not start dynamically linked executable").
        # Statically-linked providers are unaffected.
        # Fix up the ELF interpreter of any dynamically-linked provider binary so 
        # NixOS can run it.
        # `patchelf --print-interpreter` fails on static binaries, so they are 
        # skipped automatically.
        for bin in "$dir"/terraform-*; do
          if [ -f "$bin" ] && ${pkgs.patchelf}/bin/patchelf --print-interpreter "$bin" >/dev/null 2>&1; then
            ${pkgs.patchelf}/bin/patchelf --set-interpreter ${pkgs.glibc}/lib64/ld-linux-x86-64.so.2 "$bin"
          fi
        done
      '';

      passthru = {
        inherit provider-source-address provider-orig-source-address;
      };
    };

  fetchProviderSpec = {
    owner,
    repo,
    version,
    hash,
    registry,
  }:
    let 
      registry_default = 
        if registry == null 
        then "registry.opentofu.org"
        else registry;
    in pkgs.runCommand "opentofu-fetch-provider-spec-${owner}-${repo}" {
      nativeBuildInputs = with pkgs; [jq curl cacert];
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = hash;
    } ''
      set -e
      mkdir -p "$out"

      url="https://${registry_default}/v1/providers/${owner}/${repo}/versions"
      platforms=$(curl -fsS "$url" | jq -c ".versions[] | select(.version == \"${version}\") | .platforms[]")
      echo "$platforms" | while read -r p; do
        os=$(echo "$p" | jq -r .os)
        arch=$(echo "$p" | jq -r .arch)
        echo "Downloading $os/$arch spec"
        curl -fsS "https://${registry_default}/v1/providers/${owner}/${repo}/${version}/download/$os/$arch" | jq -c "{download_url,shasum}" > "$out/''${os}_''${arch}.json"
      done
    '';

  mkOpentofuProvider = {
    owner,
    repo,
    version,
    os ? pkgs.go.GOOS,
    arch ? pkgs.go.GOARCH,
    registry ? null,
    hash,
  }: let
    specs = fetchProviderSpec {inherit owner repo version hash registry;};
    spec = builtins.fromJSON (builtins.readFile "${specs}/${os}_${arch}.json");
  in
    mkTerraformProvider {
      inherit version owner repo registry;
      src = pkgs.fetchurl {
        url = spec.download_url;
        sha256 = spec.shasum;
      };
    };
}

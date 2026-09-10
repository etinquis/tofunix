{
  tflib,
  ntlib,
  pkgs,
  ...
}: {
  suites."Packaging" = {
    pos = __curPos;
    tests = [
      {
        name = "mkTerraformProvider packages a provider correctly";
        type = "script";
        script = let
          provider = tflib.mkTerraformProvider {
            owner = "hashicorp";
            repo = "null";
            version = "3.2.2";
            src = pkgs.fetchurl {
              url = "https://releases.hashicorp.com/terraform-provider-null/3.2.2/terraform-provider-null_3.2.2_linux_amd64.zip";
              hash = "sha256-Mkiq5qIZjz7IOUIY0FvV5Cvln0Ojp8C3HGbsDfCLaec=";
            };
          };
          # GOOS and GOARCH are determined by pkgs.go
          inherit (pkgs.go) GOOS GOARCH;
          provider_dir = "${provider}/libexec/terraform-providers/registry.opentofu.org/hashicorp/null/3.2.2/${GOOS}_${GOARCH}";
        in
          # sh
          ''
            ${ntlib.helpers.scriptHelpers}
            assert "-d ${provider_dir}" "Provider directory should exist at the correct path"
            # check for actual binary inside
            assert "-f ${provider_dir}/terraform-provider-null_v3.2.2_x5" "Provider binary should be in the directory"
          '';
      }
      {
        name = "mkTerraformProvider patches dynamically-linked providers for NixOS";
        type = "script";
        script = let
          # A dynamically-linked provider (Go binary linked against glibc).
          # The patchelf fix in mkTerraformProvider must set the interpreter to
          # NixOS glibc so stub-ld doesn't reject it.
          provider = tflib.mkTerraformProvider {
            owner = "blechschmidt";
            repo = "pkcs11";
            version = "0.0.11-pre";
            src = pkgs.fetchurl {
              url = "https://github.com/blechschmidt/terraform-provider-pkcs11/releases/download/v0.0.11-pre/terraform-provider-pkcs11_0.0.11-pre_linux_amd64.zip";
              hash = "sha256-cPiCvf7oO8j/N/yOQDU5Gnpuknqu031deQnAqAbNKbg=";
            };
          };
          inherit (pkgs.go) GOOS GOARCH;
          provider_dir = "${provider}/libexec/terraform-providers/registry.opentofu.org/blechschmidt/pkcs11/0.0.11-pre/${GOOS}_${GOARCH}";
          binary = "${provider_dir}/terraform-provider-pkcs11_v0.0.11-pre";
        in
          # sh
          ''
            ${ntlib.helpers.path [pkgs.patchelf]}
            ${ntlib.helpers.scriptHelpers}
            assert "-f ${binary}" "Provider binary should be in the directory"
            # The interpreter must point at the NixOS glibc dynamic linker, not
            # the stub-ld that rejects dynamically-linked executables.
            interp=$(patchelf --print-interpreter ${binary})
            assert "''${interp}" "Interpreter should be set (binary is dynamically linked)"
            assert "''${interp} != /nix/store/*/stub-ld" "Interpreter should not be the NixOS stub-ld"
            # Running the binary directly should not print the stub-ld error.
            output=$(${binary} 2>&1 || true)
            assert_not_contains "''${output}" "stub-ld" "Binary should not be rejected by stub-ld"
          '';
      }
    ];
  };
}

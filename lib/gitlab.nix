{
  pkgs,
  lib,
  source,
  wrapped,
  ...
}: let
  inherit (lib) makeBinPath getExe;

  gitlab-tofu = pkgs.stdenv.mkDerivation {
    name = "gitlab-tofu";
    src = pkgs.fetchurl {
      url = "https://gitlab.com/components/opentofu/-/raw/356937d000b7839ed717562d1e6d470b946040da/src/gitlab-tofu.sh";
      sha256 = "sha256-NQCML0ElSzCt4gHfIxDmjduZrPMZ6VKaM0T0QV5N+II=";
      executable = true;
    };
    nativeBuildInputs = [
      pkgs.makeWrapper
    ];
    phases = ["installPhase"];
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/gitlab-tofu
      chmod +x $out/bin/gitlab-tofu

      # FIX: newer opentofu versions treat `tofu "" validate` as `""` being an arg.
      #  which fails with '"" is not a command'. This removes the quotes around tf_chdir_opts
      #  so it doesn't leave empty quotes when its empty
      sed -i 's/"\''${tf_chdir_opt}"/\''${tf_chdir_opt}/g' $out/bin/gitlab-tofu

      wrapProgram $out/bin/gitlab-tofu --prefix PATH : ${
        makeBinPath [
          wrapped
          pkgs.libidn2
          pkgs.jq
          pkgs.curl
        ]
      } \
        --set-default LC_ALL "C.UTF-8" \
        --set-default LANG "C.UTF-8"
    '';
    meta.mainProgram = "gitlab-tofu";
  };
in
  pkgs.writeShellScriptBin "gitlab-tofunix" ''
    ln -s ${source} main.tf.json
    trap 'rm -f main.tf.json' EXIT
    ${getExe gitlab-tofu} "$@"
  ''

{
  pkgs,
  lib,
  ...
}:
let
  ai-commit =
    let
      binName = "ai-commit";
      src = ./ai-commit.sh;
    in
    pkgs.runCommand binName
      {
        # nativeBuildInputs = [ pkgs.makeWrapper ];
        meta = {
          mainProgram = binName;
        };
      }
      ''
        mkdir -p $out/bin
        install -m +x ${src} $out/bin/${binName}
        chmod +x $out/bin/${binName}
      '';
in
{
  packages =
    (with pkgs; [
      git
      gum
    ])
    ++ [
      ai-commit
    ];

  # https://devenv.sh/scripts/
  # scripts.ai-commit.exec = ''

  # '';

  enterShell = ''
    git --version
  '';
}

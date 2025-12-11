{
  pkgs,
  lib,
  ...
}:
let
  ai-commit =
    let
      binName = "ai-commit";
      src = ./.;
    in
    pkgs.runCommand binName
      {
        meta = {
          mainProgram = binName;
        };
      }
      ''
        mkdir -p $out/bin
        install -m +x ${src}/* $out/bin/
        mv $out/bin/${binName}.sh $out/bin/${binName}
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

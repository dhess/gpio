{ mkDerivation, base, cond, containers, directory, errors
, exceptions, filepath, free, hspec, mtl, stdenv, strict, text
, transformers
}:
mkDerivation {
  pname = "gpio";
  version = "0.4";
  src = ./.;
  libraryHaskellDepends = [
    base cond containers directory errors exceptions filepath free mtl
    strict text transformers
  ];
  testHaskellDepends = [
    base cond containers directory errors exceptions filepath free
    hspec mtl strict text transformers
  ];
  homepage = "https://github.com/dhess/gpio";
  description = "Control GPIO pins";
  license = stdenv.lib.licenses.bsd3;
}

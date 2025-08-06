{ lib }:

rec {
  /*
    capitalize "hello" -> "Hello"
    NOTE: Works on ASCII only – if you need full-Unicode case folding,
    use a separate implementation (the stock lib is ASCII-only too).
  */
  capitalize =
    (s:
      if s == "" then ""
      else
        let
          head = lib.strings.toUpper (builtins.substring 0 1 s);
          tail = builtins.substring 1 ((builtins.stringLength s) - 1) s;
        in
        "${head}${tail}");

  /*
    toLowerCamelCase "some-example_string value"
      -> "someExampleStringValue"
  */
  toLowerCamelCase =
    (s:
      let
        parts = lib.splitString "-" s;
        first = lib.strings.toLower (builtins.head parts);
        rest = map capitalize (builtins.tail parts);
      in
      lib.concatStringsSep "" ([ first ] ++ rest));
}

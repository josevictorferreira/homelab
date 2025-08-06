{ lib }:

let
  inherit (lib.strings)
    toLower toUpper splitString substring stringLength;
in
rec {
  /*
    capitalize "hello" -> "Hello"
    NOTE: Works on ASCII only – if you need full-Unicode case folding,
    use a separate implementation (the stock lib is ASCII-only too).
  */
  capitalize = str:
    if str == "" then str else
    let
      len = stringLength str;
      first = toUpper (substring 0 1 str);
    in
    "${first}${substring 1 (len - 1) str}";

  /*
    toLowerCamelCase "some-example_string value"
      -> "someExampleStringValue"
  */
  toLowerCamelCase = raw:
    let
      # Split on space, dash, or underscore
      words = lib.filter (s: s != "") (
        lib.flatten (map (splitString "_") (map (splitString "-") (splitString " " raw)))
      );

      head = toLower (lib.head words);
      tail = lib.concatMapStrings
        (w: capitalize (toLower w))
        (lib.tail words);
    in
    "${head}${tail}";
}

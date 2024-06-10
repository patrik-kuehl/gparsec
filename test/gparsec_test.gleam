import gparsec.{Parser, ParserPosition, UnexpectedEof, UnexpectedToken}
import startest.{describe, it}
import startest/expect

pub fn main() {
  startest.run(startest.default_config())
}

pub fn input_tests() {
  describe("gparsec/input", [
    it("returns a new parser", fn() {
      gparsec.input("abc", [])
      |> expect.to_be_ok()
      |> expect.to_equal(Parser(["a", "b", "c"], ParserPosition(0, 0), []))
    }),
  ])
}

pub fn token_tests() {
  describe("gparsec/token", [
    it("returns a parser that parsed a single token", fn() {
      gparsec.input("abc", "Characters: ")
      |> gparsec.token("a", fn(value, token) { value <> token })
      |> expect.to_be_ok()
      |> expect.to_equal(Parser(
        ["b", "c"],
        ParserPosition(0, 1),
        "Characters: a",
      ))
    }),
    it("returns a parser that parsed a set of tokens", fn() {
      gparsec.input("abcdefg", "Characters: ")
      |> gparsec.token("abc", fn(value, tokens) { value <> tokens })
      |> gparsec.token("def", fn(value, tokens) { value <> tokens })
      |> expect.to_be_ok()
      |> expect.to_equal(Parser(
        ["g"],
        ParserPosition(0, 6),
        "Characters: abcdef",
      ))
    }),
    it("returns a parser with a position that detected line breaks", fn() {
      gparsec.input("abc\ndef", "Characters: ")
      |> gparsec.token("abc", fn(value, tokens) { value <> tokens })
      |> gparsec.token("\n", gparsec.ignore_token)
      |> gparsec.token("def", fn(value, tokens) { value <> tokens })
      |> expect.to_be_ok()
      |> expect.to_equal(Parser([], ParserPosition(1, 3), "Characters: abcdef"))
    }),
    it("returns an error when encountering an unexpected token", fn() {
      gparsec.input("abcd", "")
      |> gparsec.token("abdz", fn(value, tokens) { value <> tokens })
      |> expect.to_be_error()
      |> expect.to_equal(UnexpectedToken(["abdz"], "abc", ParserPosition(0, 2)))
    }),
    it("returns an error when encountering an unexpected EOF", fn() {
      gparsec.input("abc", "")
      |> gparsec.token("abcd", fn(value, tokens) { value <> tokens })
      |> expect.to_be_error()
      |> expect.to_equal(UnexpectedEof(["abcd"], ParserPosition(0, 3)))
    }),
  ])
}

pub fn optional_tests() {
  describe("gparsec/optional", [
    it(
      "returns a parser that parsed a set of tokens including some optional tokens",
      fn() {
        gparsec.input("(a,b)", Pair("", ""))
        |> gparsec.optional(gparsec.token(_, "(", gparsec.ignore_token))
        |> gparsec.token("a", fn(value, token) { Pair(..value, left: token) })
        |> gparsec.token(",", gparsec.ignore_token)
        |> gparsec.token("b", fn(value, token) { Pair(..value, right: token) })
        |> gparsec.optional(gparsec.token(_, ")", gparsec.ignore_token))
        |> expect.to_be_ok()
        |> expect.to_equal(Parser([], ParserPosition(0, 5), Pair("a", "b")))
      },
    ),
    it(
      "returns a parser that parsed a set of tokens including some missing optional tokens",
      fn() {
        gparsec.input("a,b)", Pair("", ""))
        |> gparsec.optional(gparsec.token(_, "(", gparsec.ignore_token))
        |> gparsec.token("a", fn(value, token) { Pair(..value, left: token) })
        |> gparsec.token(",", gparsec.ignore_token)
        |> gparsec.token("b", fn(value, token) { Pair(..value, right: token) })
        |> gparsec.optional(gparsec.token(_, ")", gparsec.ignore_token))
        |> expect.to_be_ok()
        |> expect.to_equal(Parser([], ParserPosition(0, 4), Pair("a", "b")))
      },
    ),
    it("returns an error when a prior parser failed", fn() {
      gparsec.input("(a,b)", Pair("", ""))
      |> gparsec.token("what's going on here ...", gparsec.ignore_token)
      |> gparsec.optional(gparsec.token(_, "(", gparsec.ignore_token))
      |> gparsec.token("a", fn(value, token) { Pair(..value, left: token) })
      |> gparsec.token(",", gparsec.ignore_token)
      |> gparsec.token("b", fn(value, token) { Pair(..value, right: token) })
      |> gparsec.optional(gparsec.token(_, ")", gparsec.ignore_token))
      |> expect.to_be_error()
      |> expect.to_equal(UnexpectedToken(
        ["what's going on here ..."],
        "(",
        ParserPosition(0, 0),
      ))
    }),
  ])
}

pub fn many_tests() {
  describe("gparsec/many", [
    it("returns a parser that parsed multiple tokens", fn() {
      gparsec.input("aaab", "Characters: ")
      |> gparsec.many(gparsec.token(_, "a", fn(value, token) { value <> token }))
      |> expect.to_be_ok()
      |> expect.to_equal(Parser(["b"], ParserPosition(0, 3), "Characters: aaa"))
    }),
    it("returns a parser that parsed no tokens", fn() {
      gparsec.input("abab", "Characters: ")
      |> gparsec.many(gparsec.token(
        _,
        "aa",
        fn(value, token) { value <> token },
      ))
      |> gparsec.token("ab", fn(value, token) { value <> token })
      |> expect.to_be_ok()
      |> expect.to_equal(Parser(
        ["a", "b"],
        ParserPosition(0, 2),
        "Characters: ab",
      ))
    }),
    it("returns an error when a prior parser failed", fn() {
      gparsec.input("aaa", "Characters: ")
      |> gparsec.token("ab", fn(value, token) { value <> token })
      |> gparsec.many(gparsec.token(_, "a", fn(value, token) { value <> token }))
      |> expect.to_be_error()
      |> expect.to_equal(UnexpectedToken(["ab"], "aa", ParserPosition(0, 1)))
    }),
  ])
}

type Pair {
  Pair(left: String, right: String)
}

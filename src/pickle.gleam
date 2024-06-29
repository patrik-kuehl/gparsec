import gleam/float
import gleam/int
import gleam/regex
import gleam/result
import gleam/string

pub type ParserPosition {
  ParserPosition(row: Int, col: Int)
}

pub type Parser(a) {
  Parser(tokens: List(String), pos: ParserPosition, value: a)
}

pub type ExpectedToken {
  Literal(String)
  Pattern(String)
}

pub type ParserFailure(a) {
  UnexpectedToken(
    expected_token: ExpectedToken,
    actual_token: String,
    pos: ParserPosition,
  )
  UnexpectedEof(expected_token: ExpectedToken, pos: ParserPosition)
  GuardError(error: a, pos: ParserPosition)
}

pub type ParserResult(a, b) =
  Result(Parser(a), ParserFailure(b))

pub type ParserPredicateCallback(a) =
  fn(a) -> Bool

pub type ParserValueMapperCallback(a, b) =
  fn(a) -> b

pub type ParserTokenMapperCallback(a, b) =
  fn(a, b) -> a

pub type ParserCombinatorCallback(a, b) =
  fn(ParserResult(a, b)) -> ParserResult(a, b)

pub fn ignore_token(value: a, _: String) -> a {
  value
}

pub fn ignore_integer(value: a, _: Int) -> a {
  value
}

pub fn ignore_float(value: a, _: Float) -> a {
  value
}

pub fn parse(
  input: String,
  initial_value: a,
  parser: ParserCombinatorCallback(a, b),
) -> Result(a, ParserFailure(b)) {
  use parser <- result.try(
    Parser(string.split(input, ""), ParserPosition(0, 0), initial_value)
    |> Ok()
    |> parser(),
  )

  Ok(parser.value)
}

pub fn guard(
  prev: ParserResult(a, b),
  predicate: ParserPredicateCallback(a),
  error: b,
) -> ParserResult(a, b) {
  use parser <- result.try(prev)

  case predicate(parser.value) {
    True -> prev
    False -> GuardError(error, parser.pos) |> Error()
  }
}

pub fn map(
  prev: ParserResult(a, b),
  to: ParserValueMapperCallback(a, c),
) -> ParserResult(c, b) {
  use parser <- result.try(prev)

  Parser(parser.tokens, parser.pos, to(parser.value)) |> Ok()
}

pub fn token(
  prev: ParserResult(a, b),
  token: String,
  to: ParserTokenMapperCallback(a, String),
) -> ParserResult(a, b) {
  use previous_parser <- result.try(prev)

  use token_parser <- result.try(do_token(
    parser_from(previous_parser, ""),
    string.split(token, ""),
  ))

  parser_from(token_parser, to(previous_parser.value, token_parser.value))
}

pub fn optional(
  prev: ParserResult(a, b),
  parser: ParserCombinatorCallback(a, b),
) -> ParserResult(a, b) {
  case parser(prev) {
    Error(_) -> prev
    result -> result
  }
}

pub fn many(
  prev: ParserResult(a, b),
  initial_value: c,
  parser: ParserCombinatorCallback(c, b),
  to: ParserTokenMapperCallback(a, c),
) -> ParserResult(a, b) {
  do_many(prev, initial_value, parser, to)
}

pub fn integer(
  prev: ParserResult(a, b),
  to: ParserTokenMapperCallback(a, Int),
) -> ParserResult(a, b) {
  use previous_parser <- result.try(prev)

  use integer_parser <- result.try(case previous_parser.tokens {
    [token, ..rest]
      if token == "0"
      || token == "1"
      || token == "2"
      || token == "3"
      || token == "4"
      || token == "5"
      || token == "6"
      || token == "7"
      || token == "8"
      || token == "9"
    ->
      Parser(rest, increment_parser_position(previous_parser.pos, token), token)
      |> Ok()
      |> do_integer()
    [token, ..rest] if token == "+" || token == "-" ->
      case rest {
        [] ->
          UnexpectedEof(
            Pattern(digit_pattern),
            increment_parser_position(previous_parser.pos, token),
          )
          |> Error()
        tokens ->
          Parser(
            tokens,
            increment_parser_position(previous_parser.pos, token),
            token,
          )
          |> Ok()
          |> do_integer()
      }
    [token, ..] ->
      UnexpectedToken(Pattern(digit_pattern), token, previous_parser.pos)
      |> Error()
    [] ->
      UnexpectedEof(Pattern(digit_pattern), previous_parser.pos)
      |> Error()
  })

  case int.parse(integer_parser.value) {
    Ok(integer) ->
      Parser(
        integer_parser.tokens,
        integer_parser.pos,
        to(previous_parser.value, integer),
      )
      |> Ok()
    Error(_) ->
      UnexpectedToken(
        Pattern(digit_pattern),
        integer_parser.value,
        integer_parser.pos,
      )
      |> Error()
  }
}

pub fn float(
  prev: ParserResult(a, b),
  to: ParserTokenMapperCallback(a, Float),
) -> ParserResult(a, b) {
  use previous_parser <- result.try(prev)

  use float_parser <- result.try(case previous_parser.tokens {
    [token, ..rest]
      if token == "0"
      || token == "1"
      || token == "2"
      || token == "3"
      || token == "4"
      || token == "5"
      || token == "6"
      || token == "7"
      || token == "8"
      || token == "9"
      || token == "."
    ->
      Parser(rest, increment_parser_position(previous_parser.pos, token), token)
      |> Ok()
      |> do_float(False)
    [token, ..rest] if token == "+" || token == "-" ->
      case rest {
        [] ->
          UnexpectedEof(
            Pattern(digit_or_decimal_point_pattern),
            increment_parser_position(previous_parser.pos, token),
          )
          |> Error()
        tokens ->
          Parser(
            tokens,
            increment_parser_position(previous_parser.pos, token),
            token,
          )
          |> Ok()
          |> do_float(False)
      }
    [token, ..] ->
      UnexpectedToken(
        Pattern(digit_or_decimal_point_pattern),
        token,
        previous_parser.pos,
      )
      |> Error()
    [] ->
      UnexpectedEof(
        Pattern(digit_or_decimal_point_pattern),
        previous_parser.pos,
      )
      |> Error()
  })

  case
    float_parser.value
    |> add_integral_part_to_string_float_value()
    |> float.parse()
  {
    Ok(float) ->
      Parser(
        float_parser.tokens,
        float_parser.pos,
        to(previous_parser.value, float),
      )
      |> Ok()
    Error(_) ->
      UnexpectedToken(
        Pattern(digit_pattern),
        float_parser.value,
        float_parser.pos,
      )
      |> Error()
  }
}

pub fn until(
  prev: ParserResult(a, b),
  token: String,
  to: ParserTokenMapperCallback(a, String),
) -> ParserResult(a, b) {
  use previous_parser <- result.try(prev)

  use until_parser <- result.try(do_until(
    parser_from(previous_parser, ""),
    token,
    string.split(token, ""),
  ))

  parser_from(until_parser, to(previous_parser.value, until_parser.value))
}

pub fn skip_until(prev: ParserResult(a, b), token: String) -> ParserResult(a, b) {
  do_skip_until(prev, token, token |> string.split(""))
}

pub fn whitespace(
  prev: ParserResult(a, b),
  to: ParserTokenMapperCallback(a, String),
) -> ParserResult(a, b) {
  use previous_parser <- result.try(prev)

  use whitespace_parser <- result.try(
    parser_from(previous_parser, "") |> do_whitespace(),
  )

  parser_from(
    whitespace_parser,
    to(previous_parser.value, whitespace_parser.value),
  )
}

pub fn skip_whitespace(prev: ParserResult(a, b)) -> ParserResult(a, b) {
  use parser <- result.try(prev)

  case parser.tokens {
    [] -> prev
    [token, ..rest] ->
      case is_whitespace(token) {
        False -> prev
        True ->
          Parser(
            rest,
            increment_parser_position(parser.pos, token),
            parser.value,
          )
          |> Ok()
          |> skip_whitespace()
      }
  }
}

pub fn one_of(
  prev: ParserResult(a, b),
  parsers: List(ParserCombinatorCallback(a, b)),
) -> ParserResult(a, b) {
  use parser <- result.try(prev)

  do_one_of(prev, parser, parsers)
}

pub fn return(prev: ParserResult(a, b), value: c) -> ParserResult(c, b) {
  use parser <- result.try(prev)

  parser_from(parser, value)
}

const digit_pattern = "^[0-9]$"

const digit_or_decimal_point_pattern = "^[0-9.]$"

const whitespace_pattern = "^\\s$"

fn parser_from(prev: Parser(a), initial_value: b) -> ParserResult(b, c) {
  Parser(prev.tokens, prev.pos, initial_value) |> Ok()
}

fn do_token(
  prev: ParserResult(String, a),
  expected_tokens: List(String),
) -> ParserResult(String, a) {
  use parser <- result.try(prev)

  case expected_tokens {
    [] -> prev
    [expected_token, ..expected_rest] ->
      case parser.tokens {
        [] ->
          UnexpectedEof(
            Literal(parser.value <> string.join(expected_tokens, "")),
            parser.pos,
          )
          |> Error()
        [actual_token, ..] if expected_token != actual_token ->
          UnexpectedToken(
            Literal(parser.value <> string.join(expected_tokens, "")),
            parser.value <> actual_token,
            parser.pos,
          )
          |> Error()
        [actual_token, ..actual_rest] ->
          Parser(
            actual_rest,
            increment_parser_position(parser.pos, actual_token),
            parser.value <> actual_token,
          )
          |> Ok()
          |> do_token(expected_rest)
      }
  }
}

fn do_many(
  prev: ParserResult(a, b),
  initial_value: c,
  parser: ParserCombinatorCallback(c, b),
  to: ParserTokenMapperCallback(a, c),
) -> ParserResult(a, b) {
  use previous_parser <- result.try(prev)

  case parser(previous_parser |> parser_from(initial_value)) {
    Error(_) -> prev
    Ok(many_parser) ->
      do_many(
        parser_from(many_parser, to(previous_parser.value, many_parser.value)),
        initial_value,
        parser,
        to,
      )
  }
}

fn do_integer(prev: ParserResult(String, a)) -> ParserResult(String, a) {
  use parser <- result.try(prev)

  case parser.tokens {
    [] -> prev
    [token, ..rest] ->
      case is_digit(token) {
        False -> prev
        True ->
          Parser(
            rest,
            increment_parser_position(parser.pos, token),
            parser.value <> token,
          )
          |> Ok()
          |> do_integer()
      }
  }
}

fn do_float(
  prev: ParserResult(String, a),
  after_fraction: Bool,
) -> ParserResult(String, a) {
  use parser <- result.try(prev)

  case parser.tokens {
    [] -> prev
    [".", ..] if after_fraction -> prev
    [token, ..rest] ->
      case is_digit_or_decimal_point(token) {
        False -> prev
        True ->
          Parser(
            rest,
            increment_parser_position(parser.pos, token),
            parser.value <> token,
          )
          |> Ok()
          |> do_float(case token {
            "." -> True
            _ if after_fraction -> True
            _ -> False
          })
      }
  }
}

fn do_until(
  prev: ParserResult(String, a),
  until_token: String,
  expected_tokens: List(String),
) -> ParserResult(String, a) {
  use parser <- result.try(prev)

  case expected_tokens {
    [] -> prev
    [expected_token, ..] ->
      case parser.tokens {
        [] -> UnexpectedEof(Literal(until_token), parser.pos) |> Error()
        [actual_token, ..actual_rest] if actual_token == expected_token ->
          case
            parser.tokens
            |> string.join("")
            |> string.starts_with(until_token)
          {
            True -> prev
            False ->
              Parser(
                actual_rest,
                increment_parser_position(parser.pos, actual_token),
                parser.value <> actual_token,
              )
              |> Ok()
              |> do_until(until_token, expected_tokens)
          }
        [actual_token, ..actual_rest] ->
          Parser(
            actual_rest,
            increment_parser_position(parser.pos, actual_token),
            parser.value <> actual_token,
          )
          |> Ok()
          |> do_until(until_token, expected_tokens)
      }
  }
}

fn do_skip_until(
  prev: ParserResult(a, b),
  until_token: String,
  expected_tokens: List(String),
) -> ParserResult(a, b) {
  use parser <- result.try(prev)

  case expected_tokens {
    [] -> prev
    [expected_token, ..] ->
      case parser.tokens {
        [] -> UnexpectedEof(Literal(until_token), parser.pos) |> Error()
        [actual_token, ..actual_rest] if actual_token == expected_token ->
          case
            parser.tokens
            |> string.join("")
            |> string.starts_with(until_token)
          {
            True -> prev
            False ->
              Parser(
                actual_rest,
                increment_parser_position(parser.pos, actual_token),
                parser.value,
              )
              |> Ok()
              |> do_skip_until(until_token, expected_tokens)
          }
        [actual_token, ..actual_rest] ->
          Parser(
            actual_rest,
            increment_parser_position(parser.pos, actual_token),
            parser.value,
          )
          |> Ok()
          |> do_skip_until(until_token, expected_tokens)
      }
  }
}

fn do_whitespace(prev: ParserResult(String, a)) -> ParserResult(String, a) {
  use parser <- result.try(prev)

  case parser.tokens {
    [] -> prev
    [token, ..rest] ->
      case is_whitespace(token) {
        False -> prev
        True ->
          Parser(
            rest,
            increment_parser_position(parser.pos, token),
            parser.value <> token,
          )
          |> Ok()
          |> do_whitespace()
      }
  }
}

fn do_one_of(
  prev: ParserResult(a, b),
  entrypoint_parser: Parser(a),
  parsers: List(ParserCombinatorCallback(a, b)),
) -> ParserResult(a, b) {
  case parsers {
    [] -> prev
    [parser, ..rest] ->
      case entrypoint_parser |> Ok() |> parser() {
        Ok(parser) -> Ok(parser)
        result -> do_one_of(result, entrypoint_parser, rest)
      }
  }
}

fn add_integral_part_to_string_float_value(float_as_string: String) -> String {
  case float_as_string |> string.split("") {
    [".", ..rest] -> "0." <> string.join(rest, "")
    ["-", ..rest] ->
      case rest {
        [".", ..fraction] -> "-0." <> string.join(fraction, "")
        float -> "-" <> string.join(float, "")
      }
    float -> float |> string.join("")
  }
}

fn increment_parser_position(
  prev: ParserPosition,
  recent_token: String,
) -> ParserPosition {
  case recent_token {
    "\n" -> ParserPosition(prev.row + 1, 0)
    _ -> ParserPosition(prev.row, prev.col + 1)
  }
}

fn matches_pattern(token: String, pattern: String) -> Bool {
  case regex.from_string(pattern) {
    Error(_) -> False
    Ok(pattern) -> regex.check(pattern, token)
  }
}

fn is_digit(token: String) -> Bool {
  matches_pattern(token, digit_pattern)
}

fn is_digit_or_decimal_point(token: String) -> Bool {
  matches_pattern(token, digit_or_decimal_point_pattern)
}

fn is_whitespace(token: String) -> Bool {
  matches_pattern(token, whitespace_pattern)
}

_ = require 'underscore-plus'

# Grammar implemented here:
# bibtex -> (string | preamble | comment | entry)*
# string -> '@STRING' '{' key_equals_value '}'
# preamble -> '@PREAMBLE' '{' value '}'
# comment -> '@COMMENT' '{' value '}'
# entry -> '@' key '{' key ',' key_value_list '}'
# key_value_list -> key_equals_value (',' key_equals_value)*
# key_equals_value -> key '=' value
# value -> value_quotes | value_braces | string_key | string_concat
# string_concat -> value '#' value
# value_quotes -> '"' .*? '"'
# value_braces -> '{' .*? '}'
#
# N.B. value_braces is not a valid expansion of string_concat

class BibtexParser
  strings: {}
  preambles: []
  bibtexEntries: []

  constructor: (@bibtex) ->
    #pass

  parse: ->
    @bibtexEntries = @findEntryPositions @findInterstices()

    for entry in @bibtexEntries
      [entryType, entryBody] = @splitEntryTypeAndBody entry

      if not entryType then break # Skip this entry.

      entry = switch entryType.toLowerCase()
        when 'string' then @stringEntry entryBody
        when 'preamble' then @preambleEntry entryBody
        when 'comment' then @commentEntry entryBody
        else @keyedEntry entryType, entryBody

      if entry
        @entries.push entry

    return @entries

  findInterstices: ->
    intersticePattern = /}\s*@/gm
    interstices = @bibtex.match intersticePattern

    # Add the start of the first entry.
    interstices.unshift @bibtex.substring 0, @bibtex.indexOf('@') + 1

    return interstices

  findEntryPositions: (intersticeStrings) ->
    entryPositions = []
    position = 0

    previous = intersticeStrings.shift()

    for interstice in intersticeStrings
      beginning = @bibtex.indexOf(previous, position) + previous.length
      end = @bibtex.indexOf interstice, beginning

      # Wasn't a true interstice; don't break the entry there.
      if @isEscapedWithBackslash(interstice, end) then break

      entryPositions.push [beginning, end - 1]

      position = end
      previous = interstice

    return entryPositions

  splitEntryTypeAndBody: (entry) ->
    entry = @bibtex[entry[0]..entry[1]]

    # Look ahead for '{' which is not escaped with backslashes.
    end = entry.indexOf '{'

    if end is -1
      return false

    [
      entry[0...end]
      entryBody: entry[(end + 1)...]
    ]

  stringEntry: (entryBody) ->
    [key, value] = _.map(entryBody.split('='), (s) ->
      s.replace(/^(?:\s")+|(?:\s")+$/g, '')
    )

    @string[key] = value

    return false

  preambleEntry: (entryBody) ->


    @preambles.push entryBody

    return false

  commentEntry: ->
    #pass

  keyedEntry: (key) ->
    #pass

  isEscapedWithBackslash: (text, position) ->
    slashes = 0
    position--

    while text[position] is '\\'
      slashes++
      position--

    slashes % 2 is 1

  isEscapedWithBrackets: (text, position) ->
    @previousCharacter(text, position) is '{' \
    and @nextCharacter(text, position) is '}'

  isDelimitedText: (text, position) ->
    @isQuotedText(text, position) \
    or @isBracketedText(text, position) \
    or @isParenthesizedText(text, position)

  isQuotedText: (text, position) ->
    # {a\"#\"b} -> false
    # "a{"}#b\" -> true
    # "a" # "b" -> false
    # {ab"#{"} -> true # Would we ever test this?

    # occurences = 0
    # position = 0
    #
    # while (position = text.indexOf '"', position) isnt -1
    #   if @isEscapedWithBracketstext[position]
    #
    # _.size(char for index, char of text[0...position] \
    #   when char is '"' \
    #   and not (@previousCharacter(text, index) is '{') \
    #     and (@nextCharacter(text, index) is '}'))

  isBracketedText: (text, position) ->
    left = @countOccurencesOfCharacterInText text[0...position], '{'
    right = @countOccurencesOfCharacterInText text[0...position], '}'

    left is right

  isParenthesizedText: (text, position) ->
    left = @countOccurencesOfCharacterInText text[0...position], '('
    right = @countOccurencesOfCharacterInText text[0...position], ')'

    left is right

  countOccurencesOfCharacterInText: (text, character) ->
    occurences = 0
    position = 0

    while (position = text.indexOf character, position) isnt -1
      if not @isEscapedWithBackslash(text, position) then occurences++

      position++

    return occurences

  nextCharacter: (text, position) ->
    text[position * 1 + 1]

  previousCharacter: (text, position) ->
    text[position * 1 - 1]

@bibtexParse =
  toJSON: (bibtex) ->
    parser = new BibtexParser bibtex

    parser.parse()
  toBibtex: (json) ->
    # pass

if module.exports?
  module.exports = @bibtexParse

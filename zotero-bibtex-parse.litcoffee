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
  strings: {
    jan: 'January'
    feb: 'February'
    mar: 'March'
    apr: 'April'
    may: 'May'
    jun: 'June'
    jul: 'July'
    aug: 'August'
    sep: 'September'
    oct: 'October'
    nov: 'November'
    dec: 'December'
  }

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
    # Handle possible string concatenation.

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

  isNumeric: (text) ->
    not _.isBoolean(text) and not _.isNaN(text * 1)

  splitValueByDelimeters: (text) ->
    # "value is either :
    #   an integer,
    #   everything in between braces,
    #   or everything between quotes.
    #   ...also...a single word can be valid if it has been defined as a string.
    #   [also, string concatenation]"
    #
    # "Inside the braces, you can have arbitrarily nested pairs of braces.
    # But braces must also be balanced inside quotes!
    # Inside quotes, ... You must place [additional] quotes inside braces.
    # You can have a @ inside a quoted values but not inside a braced value."

    text = text.trim()

    if @isNumeric text then return text * 1

    # If first character is quotation mark, use nextDelimitingQuotationMark
    # and go from there. Pursue similar policy with brackets.
    split = []
    delimiter = text[0]
    position = 0

    switch delimiter
      when '"'
        position = @nextDelimitingQuotationMark(text[1..])
      when '{'
        position = @nextDelimitingBracket
      when '#'
        # Keep moving. Evaluated strings and values will automatically be joined.
        position = 1
      else
        # Get string-y bit ("The placeholder (variable/string name) must start
        # with a letter and can contain any character in [a-z,A-Z,_,0-9].") and
        # check it against the dictionary of strings.
        stringPattern = /^a-z[a-z_0-9]+/gi
        stringPattern.match text

        string = text[...stringPattern.lastIndex]

        if @strings[string]?
          return [@strings[string]]

    # Something has gone wrong. Return the original, unsplit value.
    if not position then return [text]

    split.push text[1...position]

    if position < text.length - 1
      split = split.concat @splitValueByDelimeters text[(position + 1)..]

    return split

  nextDelimitingQuotationMark: (text) ->
    position = text.indexOf '"'

    # When the quotation mark is surrounded by unescaped brackets, keep looking.
    while text[position - 1] is '{' and text[position - 2] isnt '\\' \
    and text[position + 1] is '}' and position isnt -1
      position = text.indexOf '"', position + 1

    if position is -1 then return false

    position

  nextDelimitingBracket: (text) ->
    open = 1
    closed = 0

    for position, character of text
      if character is '{' and not @isEscapedWithBackslash(text, position)
        open++
      else if character is '}' and not @isEscapedWithBackslash(text, position)
        closed++

      if open is closed then return position

    return false

  countOccurencesOfCharacterInText: (text, character, isEscapableWithBackslash = true) ->
    occurences = 0
    position = 0

    while (position = text.indexOf character, position) isnt -1
      if isEscapableWithBackslash
        if not @isEscapedWithBackslash(text, position) then occurences++
      else
        occurrences++

      position++

    return occurences

@bibtexParse =
  toJSON: (bibtex) ->
    parser = new BibtexParser bibtex

    parser.parse()
  toBibtex: (json) ->
    # pass

if module.exports?
  module.exports = @bibtexParse

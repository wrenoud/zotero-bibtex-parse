_ = require 'underscore-plus'

# Grammar implemented here:
# bibtex -> (string | preamble | comment | entry)*
# string -> '@STRING' '{' key_equals_value '}'
# preamble -> '@PREAMBLE' '{' value '}'
# comment -> '@COMMENT' '{' value '}'
# entry -> '@' key '{' key ',' key_value_list '}'
# key_value_list -> key_equals_value (',' key_equals_value)*
# key_equals_value -> key '=' value
# value -> value_quotes | value_braces | key
# value_quotes -> '"' .*? '"'
# value_braces -> '{' .*? '}'

class BibtexParser
  strings: {}

  bibtexEntries: []

  constructor: (@bibtex) ->
    #pass

  parse: ->
    @bibtexEntries = @findEntries @findInterstices()

    for entry in @bibtexEntries
      [entryType, entryBody] = @entryType entry

      if not entryType then break # Skip this entry.

      if _.isString entryType
        entryType = entryType.toLowerCase()

      switch entryType
        when 'string' then @stringEntry entryBody
        when 'preamble' then @preambleEntry entryBody
        when 'comment' then @commentEntry entryBody
        else @keyedEntry entryType, entryBody

      @entries.push #something

    return @entries

  findInterstices: ->
    intersticePattern = /}\s+@/gm
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

      if @isEscaped end then break # Wasn't a true interstice; don't break the
                                   # entry there.

      entryPositions.push [beginning, end - 1]

      position = end
      previous = interstice

    return entryPositions

  splitEntryTypeAndBody: (entry) ->
    # Look ahead for '{' which is not escaped with backslashes.
    end = entry.indexOf '{'

    while (@isEscaped(end) or @isQuoted(end)) and end isnt -1
      end = entry.indexOf '{', (end + 1)

    if end is -1
      return false

    {
      type: entry[position...end]
      body: entry[(end + 1)...]
    }

  stringEntry: ->
    #pass

  preambleEntry: ->
    #pass

  commentEntry: ->
    #pass

  keyedEntry: (key) ->
    #pass

  isEscaped: (entry, position) ->
    slashes = 0
    position--

    while entry[position] is '\\'
      slashes++
      position--

    slashes % 2 is 1

  isQuoted: (entry, position) ->
    range = entry[0...position]
    position = 0
    doubleQuotes = 0
    singleQuotes = 0

    while position = range.indexOf('"', position) \
    and not @isEscaped range, position
      doubleQuotes++

    while position = range.indexOf("'", position) \
    and not @isEscaped range, position
      singleQuotes++

    (doubleQuotes % 2 is 1) or (singleQuotes % 2 is 1)

@bibtexParse =
  toJSON: (bibtex) ->
    parser = new BibtexParser bibtex

    parser.parse()
  toBibtex: (json) ->
    # pass

if module.exports?
  module.exports = @bibtexParse

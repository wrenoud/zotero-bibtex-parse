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
  position: 0
  entries: []
  strings: {}

  constructor: (@bibtex) ->


  parse: ->
    while @nextEntry()
      if _.isString(entryType = @entryType())
        entryType = entryType.toLowerCase()

      switch entryType
        when 'string' then @stringEntry()
        when 'preamble' then @preambleEntry()
        when 'comment' then @commentEntry()
        else @keyedEntry(entryType)

      @entries.push #something

    return @entries

  nextEntry: ->
    @position = @bibtex.indexOf('@', @position) + 1

  entryType: ->
    # Look ahead for '{' which is not preceded by a single backslash.
    # Really should be looking for nor preceded by an odd number of backslashes.
    end = @bibtex.indexOf '{', @position

    until not @isEscaped(end) \
    or end is -1
      end = @bibtex.indexOf '{', @position

    if end is -1
      return false

    [position, @position] = [@position, end + 1]

    @bibtex[position...end]

  entryBody: ->
    brackets = 0
    position = @position

    endMarker = /}\s@/

    end = @bibtex.indexOf

    # look for next instance of } <whitespace> @
    # how to make sure it isn't inside {} or ""?
    # >> do this by counting open and close brackets to make sure they come out
    # the same
    # >> count quotes to make sure there are an even number
    # skip brackets/quotes proceeded by odd number of \

  stringEntry: ->
    #pass

  preambleEntry: ->
    #pass

  commentEntry: ->
    #pass

  keyedEntry: (key) ->
    #pass

  isEscaped: (position) ->
    slashes = 0

    while @bibtex[position] is '\\'
      slashes++
      position--

    slashes % 2 is 1

@bibtexParse =
  toJSON: (bibtex) ->
    parser = new BibtexParser bibtex

    parser.parse()
  toBibtex: (json) ->
    # pass

if module.exports?
  module.exports = @bibtexParse

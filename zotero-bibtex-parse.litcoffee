This file attempts to parse Zotero-generated BibTeX citation files according to
this [documentation](http://maverick.inria.fr/~Xavier.Decoret/resources/xdkbibtex/bibtex_summary.html)
(while still being lenient enough to handle what Zotero can sometimes output)
and present it as useful JSON.

The grammar understood here is roughly:

```
bibtex -> (string | preamble | comment | entry)*
string -> '@STRING' '{' key_equals_value '}'
preamble -> '@PREAMBLE' '{' value '}'
comment -> '@COMMENT' '{' value '}'
entry -> '@' key '{' key ',' key_value_list '}'
key_value_list -> key_equals_value (',' key_equals_value)*
key_equals_value -> key '=' value
value -> value_quotes | value_braces | string_key | string_concat
string_concat -> value '#' value
value_quotes -> '"' .*? '"'
value_braces -> '{' .*? '}'
```

N.B. `value_braces` is not a valid expression in `string_concat`

    _ = require 'underscore-plus'

It doesn't seem worth importing a utility library for these.

    toNumber = (value) ->
      value * 1

    isNumeric = (value) ->
      not _.isBoolean(value) and not _.isNaN(toNumber value)

    trimTrailingComma = (value) ->
      if _.last(value) is ',' then value = value[...(value.length - 1)]

      return value

Essentially `Array.join`, but if the array is only one element, return that
element intact.

This prevents turning arrays with a single numeric element into strings.

    safelyJoinArrayElements = (array, separator) ->
      if array.length > 1
        array.join(separator)
      else
        array[0]

Start defining the parser:

    module.exports = class BibtexParser

Additional values are added to this dictionary when the parser encounters a
`@string` entry.

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

The `preambles` array holds the contents of `@preamble` entries. String
variables are parsed and concatenated.

The `comments` array holds the unmodified contents of `@comment` entries.
Comments which are not part of formal `@comments` entries are currently ignored.

The `entries` array holds the parsed `@<key>` citation entries.

When I'm ready to break backwards-compatibility, these will be merged into one
array which preserves the order of the entries.

      preambles: []
      comments: []
      entries: []

      toNumber: toNumber

      constructor: (@bibtex) ->
        #pass

      parse: ->
        bibtexEntries = @findEntries()

        for entry in bibtexEntries
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

      findEntries: ->
        ats = []
        position = 0

Find all the `@`s that are not escaped.

        while (position = @bibtex.indexOf('@', position)) isnt -1
          if not @isEscapedWithBackslash(@bibtex[position])
            ats.push position

          position++

        entries = []
        numberOfEntries = ats.length

For each of the `@`s that is not escaped:
1. Get the next such `@`
2. Look backwards from it for the most recent closing bracket
3. ...that's the end of the entry


        for index, position of ats
          index = toNumber(index) # It's assumed a string key.

          start = position + 1

          if index + 1 < numberOfEntries
            next = ats[index + 1]
          else
            next = @bibtex.length - 1

          end = _.lastIndexOf @bibtex[...next], '}'

          entries.push @bibtex[start...end]

        return entries

      splitEntryTypeAndBody: (entry) ->
        # Look ahead for '{' which is not escaped with backslashes.
        end = entry.indexOf '{'

        if end is -1
          return false

        [
          entry[0...end]
          entry[(end + 1)...]
        ]

      stringEntry: (entryBody) ->

Splits the incoming string by the equals sign and then performs the equivalent
of `s.trim()` and removing leading or trailing quotations from each portion.

        [key, value] =_.map(entryBody.split('='), (s) ->
          s.replace(/^(?:\s"?)+|(?:"?\s)+$/g, '')
        )

        @strings[key] = value

        return false

      preambleEntry: (entryBody) ->

Handle possible string concatenation.

        @preambles.push safelyJoinArrayElements(@splitValueByDelimiters(entryBody), '')

        return false

      commentEntry: (entryBody) ->

        @commentEntry.push entryBody

        return false

      keyedEntry: (key, body) ->

        entry = {
          entryType: key
          citationKey: ''
          entryTags: {}
        }

Split entry body by line:

        body = body.split('\n')

The first line is the citation key (minus any trailing comma).

        entry.citationKey = trimTrailingComma body.shift()

Iterate over the remaining lines of the body and parse the tags:

        for line in body
          [key, value] = _.invoke(line.split('='), 'trim')

Blank lines will not have a valid `key = value`, so ignore.

          if value

If the line ended in a comma, ignore it.

            value = trimTrailingComma value

            entry.entryTags[key] = safelyJoinArrayElements(@splitValueByDelimiters(value), '')

        return entry

      isEscapedWithBackslash: (text, position) ->
        slashes = 0
        position--

        while text[position] is '\\'
          slashes++
          position--

        slashes % 2 is 1

> value is either :
> * an integer,
> * everything in between braces,
> * or everything between quotes.
> * ...also...a single word can be valid if it has been defined as a string.
> * [also, string concatenation]


> Inside the braces, you can have arbitrarily nested pairs of braces. But braces
> must also be balanced inside quotes! Inside quotes, ... You must place
> [additional] quotes inside braces. You can have a `@` inside a quoted values
> but not inside a braced value.

      splitValueByDelimiters: (text) ->
        text = text.trim()

        if isNumeric text then return [text * 1]

        # If first character is quotation mark, use nextDelimitingQuotationMark
        # and go from there. Pursue similar policy with brackets.
        split = []
        delimiter = text[0]
        position = 0
        value = ''

        switch delimiter
          when '"'
            position = toNumber(@nextDelimitingQuotationMark(text[1..])) + 1

            value = text[1...position]
          when '{'
            position = toNumber(@nextDelimitingBracket(text[1..])) + 1

            value = text[1...position]
          when '#'
            # Keep moving. Evaluated strings and values will automatically be
            # joined.
            position = 1
          else

Get string-y bit:

> The placeholder (variable/string name) must start with a letter and can
> contain any character in `[a-z,A-Z,_,0-9]`.

and check it against the dictionary of strings.

            stringPattern = /^[a-z][a-z_0-9]*/gi
            stringPattern.exec text

            position = stringPattern.lastIndex
            string = text[...position]

            if @strings[string]?
              value = @strings[string]

If:

* the initial delimiter was a quote and the closing quote wasn't found,
* the initial delimiter was an open brace and the closing brace wasn't found, or
* the initial delimiter was not `"`, `{`, `#`, or an alphabetic character

then position is 0 and value is an empty string—text was effectively
unparseable, so it should be returned unchanged.


        if not position then return [text]

        if value
          split.push value

        if position < text.length - 1
          split = split.concat @splitValueByDelimiters(text[(position + 1)..])

        return split

      nextDelimitingQuotationMark: (text) ->
        position = text.indexOf '"'

        # When the quotation mark is surrounded by unescaped brackets, keep looking.
        while text[position - 1] is '{' and text[position - 2] isnt '\\' \
        and text[position + 1] is '}' and position isnt -1
          position = text.indexOf '"', position + 1

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

        return -1

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

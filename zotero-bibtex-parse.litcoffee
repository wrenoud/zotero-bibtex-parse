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
value -> value_quotes | value_braces | string_concat | string_key | number
string_concat -> value '#' value
value_quotes -> '"' .*? '"'
value_braces -> '{' .*? '}'
```

N.B. `value_braces` is not technically a valid expression in `string_concat`,
but this parser accepts it.

    _ = require 'underscore-plus'

It doesn't seem worth importing a utility library for these.

    toNumber = (value) ->
      value * 1

    isNumeric = (value) ->
      not _.isBoolean(value) and not _.isNaN(toNumber value)

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

The `entries` array holds three types of entries:
1. The contents of `@preamble` entries. String variables are parsed and
   concatenated.
2. The unmodified contents of `@comment` entries. Comments which are not part of
   formal `@comments` entries are currently ignored.
3. The parsed `@<key>` citation entries.


      entries: []

      toNumber: toNumber

      constructor: (@bibtex) ->
        return

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

Find all `@`s.

        while (position = @bibtex.indexOf('@', position)) isnt -1
          ats.push position

          position++

Filter the `@`s so that only the ones outside of quotes are kept.

        delimitingAts = []
        lastDelimitingAt = 0

        for position in ats
          if @areStringDelimitersBalanced @bibtex[lastDelimitingAt...position]
            delimitingAts.push lastDelimitingAt = position

        entries = []
        lastDelimitingAt = _.first delimitingAts
        delimitingAts = _.rest(delimitingAts).concat(@bibtex.length)

For each of the delimiting `@`s:
1. Get the next such `@`
2. Look backwards from it for the most recent closing bracket
3. ...that's the end of the entry


        for position in delimitingAts
          start = lastDelimitingAt + 1

          end = _.lastIndexOf @bibtex[...position], '}'

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
        entry = {
          entryType: 'preamble'

Handle possible string concatenation.

          entry: safelyJoinArrayElements(@splitValueByDelimiters(entryBody), '')
        }

      commentEntry: (entryBody) ->
        entry = {
          entryType: 'comment'
          entry: entryBody
        }

      keyedEntry: (key, body) ->

        entry = {
          entryType: key
          citationKey: ''
          entryTags: {}
        }

Split entry body by comma which are neither in quotes nor brackets:

        fields = @findFieldsInEntryBody body

The first field is the citation key.

        entry.citationKey = fields.shift()

Iterate over the remaining fields and parse the tags:

        for field in fields
          [key, value] = _.invoke(@splitKeyAndValue(field), 'trim')

Ignore lines without a valid `key = value`.

          if value
            entry.entryTags[key] = safelyJoinArrayElements(@splitValueByDelimiters(value), '')

        return entry

      findFieldsInEntryBody: (body) ->
        commas = []
        position = 0

        while (position = body.indexOf(',', position)) isnt -1
          commas.push position

          position++

        delimitingCommas = []
        lastDelimitingComma = 0

        for position in commas
          if @areStringDelimitersBalanced body[lastDelimitingComma...position]
            delimitingCommas.push lastDelimitingComma = position

        fields = []
        lastDelimitingComma = 0

        for position in delimitingCommas
          fields.push body[lastDelimitingComma...position]

          lastDelimitingComma = position + 1

        return fields

> ...some characters can not be put directly into a BibTeX-entry, as they would
> conflict with the format description, like {, " or $. They need to be escaped
> using a backslash (\).

(http://www.bibtex.org/SpecialSymbols/)

      isEscapedWithBackslash: (text, position) ->
        slashes = 0
        position--

        while text[position] is '\\'
          slashes++
          position--

        slashes % 2 is 1

      isEscapedWithBrackets: (text, position) ->
        text[position - 1] is '{' \
        and @isEscapedWithBackslash(text, position - 1) \
        and text[position + 1] is '}' \

Probably we could safely ignore a case like `@isEscapedWithBracket '\\{\\}', 2`.

        and @isEscapedWithBackslash(text, position + 1)

      splitKeyAndValue: (text) ->
        if (position = text.indexOf('=')) isnt -1
          return [
            text[...position]
            text[(position + 1)..]
          ]
        else
          return [text]

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
        numberOfOpeningBrackets = 1
        numberOfClosingBrackets = 0

        for position, character of text
          if character is '{' and not @isEscapedWithBackslash(text, position)
            numberOfOpeningBrackets++
          else if character is '}' and not @isEscapedWithBackslash(text, position)
            numberOfClosingBrackets++

          if numberOfOpeningBrackets is numberOfClosingBrackets then return position

        return -1

      areStringDelimitersBalanced: (text, start, end) ->
        numberOfOpenBrackets = 0
        numberOfQuotationMarks = 0

        for position, character of text[start..end]
          if character is '{' and not @isEscapedWithBackslash(text, toNumber(position))
            numberOfOpenBrackets++
          else if character is '}' and not @isEscapedWithBackslash(text, toNumber(position))
            numberOfOpenBrackets--
          else if character is '"' and not @isEscapedWithBrackets(text, toNumber(position))
            numberOfQuotationMarks++

        numberOfOpenBrackets is 0 and numberOfQuotationMarks % 2 is 0

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
      constructor: (@bibtex) ->

Additional values are added to this dictionary when the parser encounters a
`@string` entry.

        @strings = {
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


        @entries = []

        return

      parse: ->
        bibtexEntries = @findEntries()

        for entry in bibtexEntries
          [entryType, entryBody] = _.invoke(entry, 'trim')

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

Filter the `@`s so that only the ones outside of string delimiters are kept.

        delimitingAts = []
        lastDelimitingAt = 0

        for position in ats
          if @areEntryDelimitersBalanced @bibtex[lastDelimitingAt...position]
            delimitingAts.push lastDelimitingAt = position

        entries = []
        lastDelimitingAt = _.first delimitingAts
        delimitingAts = _.rest(delimitingAts).concat(@bibtex.length)

For each of the delimiting `@`s:
1. Get the next unescaped opening parenthesis or bracket
2. Look for the next delimiting closing parenthesis or bracket
3. ...that's the end of the entry


        for position in delimitingAts
          possibleEntry = @bibtex[lastDelimitingAt...position]

          lastDelimitingAt = position

          for index, character of possibleEntry
            if (character is '{' or character is '(') and not @isEscapedWithBackslash(possibleEntry, character)
              startOfBody = toNumber index
              break

If there were no unescaped opening parentheses or brackets, this block can't be
parsed—just skip it.

          if not startOfBody?
            break

          delimitingCharacter = possibleEntry[startOfBody]

          switch delimitingCharacter
            when '{'
              lengthOfBody = @nextDelimitingBracket possibleEntry[(startOfBody + 1)..]
            when '('
              lengthOfBody = @nextDelimitingParenthesis possibleEntry[(startOfBody + 1)..]

If lengthOfBody is -1, a closing delimiter couldn't be found. Because the parser
ignores `@`s which are inside delimiters, this shouldn't happen unless this is
the last entry in the file.

          if lengthOfBody? and lengthOfBody isnt -1
            endOfBody = startOfBody + lengthOfBody + 1
          else
            endOfBody = possibleEntry.length

          entries.push [
            possibleEntry[1...startOfBody]
            possibleEntry[(startOfBody + 1)...endOfBody]
          ]

Check for an informal comment (any text that isn't inside an `@` block) and
append it if there happens to be one.

          informalCommentEntry = @informalCommentEntry(possibleEntry[(endOfBody + 1)..])

          if informalCommentEntry
            entries.push informalCommentEntry

        return entries

      stringEntry: (entryBody) ->

Splits the incoming string by the equals sign and then performs the equivalent
of `s.trim()` and removing leading or trailing quotations from each portion.

        [key, value] =_.map(entryBody.split('='), (s) ->
          s.replace(/^(?:\s*"?)+|(?:"?\s*)+$/g, '')
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

      informalCommentEntry: (possibleEntryBody) ->
        possibleEntryBody = possibleEntryBody.trim()

        if possibleEntryBody.length is 0
          return false

        entry = {
          entryType: 'comment'
          entry: possibleEntryBody
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

        delimitingCommas.push body.length

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
        while @isEscapedWithBrackets text, position
          position = text.indexOf '"', position + 1

        position

      nextDelimitingBracket: (text) ->
        numberOfOpenBrackets = 1

        for position, character of text
          position = toNumber position

          if character is '{' and not @isEscapedWithBackslash(text, position)
            numberOfOpenBrackets++
          else if character is '}' and not @isEscapedWithBackslash(text, position)
            numberOfOpenBrackets--

          if numberOfOpenBrackets is 0 then return position

        return -1

      nextDelimitingParenthesis: (text) ->
        numberOfOpenParentheses = 1

        for position, character of text
          position = toNumber position

          if character is '(' and not @isEscapedWithBackslash(text, position)
            numberOfOpenParentheses++
          else if character is ')' and not @isEscapedWithBackslash(text, position)
            numberOfOpenParentheses--

          if numberOfOpenParentheses is 0 then return position

        return -1

      areEntryDelimitersBalanced: (text) ->
        numberOfOpenBrackets = 0
        numberOfOpenParentheses = 0
        numberOfQuotationMarks = 0

        for position, character of text
          position = toNumber position

          if character is '{' and not @isEscapedWithBackslash(text, position)
            numberOfOpenBrackets++
          else if character is '}' and not @isEscapedWithBackslash(text, position)
            numberOfOpenBrackets--
          else if character is '(' and not @isEscapedWithBackslash(text, position)
            numberOfOpenParentheses++
          else if character is ')' and not @isEscapedWithBackslash(text, position)
            numberOfOpenParentheses--
          else if character is '"' and not @isEscapedWithBrackets(text, position)
            numberOfQuotationMarks++

        numberOfOpenBrackets is 0 and numberOfQuotationMarks % 2 is 0

      areStringDelimitersBalanced: (text) ->
        numberOfOpenBrackets = 0
        numberOfQuotationMarks = 0

        for position, character of text
          position = toNumber position

          if character is '{' and not @isEscapedWithBackslash(text, position)
            numberOfOpenBrackets++
          else if character is '}' and not @isEscapedWithBackslash(text, position)
            numberOfOpenBrackets--
          else if character is '"' and not @isEscapedWithBrackets(text, position)
            numberOfQuotationMarks++

        numberOfOpenBrackets is 0 and numberOfQuotationMarks % 2 is 0

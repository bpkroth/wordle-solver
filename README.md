# wordle-solver

A quick and relatively simple shell script to help solve [wordle](https://wordlegame.org/) (and even its evil twin [absurdle](https://qntm.org/files/wordle/index.html)) puzzles.

## Requirements

Tested on Ubuntu 20.04.
Probably works on most Debian based things with `bash`.
Others could also be made to work if you add the appropriate packages (e.g. `curl`, `jq`, etc. - see source for more details.)

## Usage

```text
# ./wordle-solver.sh string-length [<guess-string:dot-delimited-result-string>]*
```

Requires an initial integer argument denoting the string length for the puzzle you're solving.

The remaining arguments are your guesses and results of those guesses represented by combo strings separated by a `:` colon:

1. `guess-string` is the guess word you made
2. `dot-delimited-result-string` encodes the result color indicators from the game as characters:
    - `gray` (a non match) is represented by a `.` period (dot)
        - Background: `.` is the wildcard character in [regular expressions](https://en.wikipedia.org/wiki/Regular_expression#POSIX_basic_and_extended).
    - `yellow` (an included letter but in the wrong position) is represented by a lowercase version of that letter (e.g. `s`)
    - `green` (correct letter, correct position) is represented by an uppercase version (e.g. `S`) of that letter in that position

Results are returned in two sets:

1. Words without any repeated letters.

    Words without repeated letters should generally be tried first since they have the potential to gain more information.

2. Words with repeated letters.

    These can basically be treated as a guess of last resort.

The program uses the arguments to construct regular expressions to search in both the wordle dictionary and a system dictionary.

From there it uses single English language letter frequency analysis to try to refine the set of suggested next guesses down to a reasonably small set.

### Example

1. Start with an initial guess based on 5 letter words that appear in either the wordle dictionary (see source code for `wordle_words_url`) or the system dictionary (currently set to do that as a last resort in case no words are found in the wordle dictionary).

    ```text
    # ./wordle-solver.sh 5

    === Possible match suggestions without repeat letters (better for early guesses) ===

    atone
    tenia
    tinea

    === Possible match suggestions with repeat letters ===

    anent
    eaten
    inane
    ninon
    onion
    taint
    tanto
    tenet
    tenon
    titan
    tonne
    ```

    We pick one of these to input to the game, get its results, and then feed it back to the program.  For instance

    Input: "atone"

    Returns:
    - e is included but in the wrong spot.

2. Generate a next guess by including the details from the last guess as a new argument.

    This will construct a more refined regular expression from the inputs to remove letters that did not match at all (e.g. `[aton]` in this case), or did not match in a given position (`e` in the 5th slot in this case).

    ```text
    # ./wordle-solver.sh 5 atone:....e

    === Possible match suggestions without repeat letters (better for early guesses) ===

    heirs
    hires

    === Possible match suggestions with repeat letters ===

    esses
    issei
    ```

    Input: "heirs"

    Returns:
    - S is correct
    - e is include but in the wrong spot.

3. Next guess we add `heirs:.e..S` to the arguments since `heirs` was guessed, `e` was correct but wrong location, `S` (encoded as a capital letter) was correct, and all others were still incorrect.

    ```txt
    # ./wordle-solver.sh 5 atone:....e heirs:.e..S

    === Possible match suggestions without repeat letters (better for early guesses) ===

    clews
    clues
    culms
    duces
    duels
    flues
    fuels
    fumes
    mules

    === Possible match suggestions with repeat letters ===

    culls
    dudes
    dulls
    esses
    lulls
    sleds
    ```

4. And so on ...

## Notes

### Why `bash` !?

Yeah, I know, but this was a quick lark in between meetings.  As I added more features I definitely regretted that choice somewhat, but whatever, it works well enough, let's move on now :P

### Why isn't this isn't fully automated?

I haven't (yet) bothered to integrate it with something like `phantomjs` or `selenium` to automatically interact with the web pages.  See above about quick and hackish choice of `bash` :P

### Improved next guess suggestion rankings?

Using more complex language frequency information like digrams, trigrams, beginning and ending sequences, would be a better way to rank results.
For now, they are simply ranked by single letter frequency.
To do this we take words matching the overall regular expression subset obtained from the arguments and applied to the dictionaries and then iteratively remove the least frequent letter from set until there are either "few enough" results (for a human to look at) or no more results, in which case we use the previously non-empty set.

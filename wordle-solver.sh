#!/bin/bash
# wordle-solver.sh
# bpkroth
# 2022-01-18

set -eu
set -o pipefail

scriptdir=$(dirname $(readlink -f $0))
cd "$scriptdir"

use_sysdict_words_file=false

sysdict_words_file='/usr/share/dict/american-english-insane'
wordle_words_file='wordle_words.txt'
wordle_words_url='https://wordlegame.org/assets/js/wordle/en.js?v4'
wordle_words_js='wordle.js'

# Install some dependencies in case they're missing.
if [ ! -f "$sysdict_words_file" ] || ! type jq curl >/dev/null; then
    set -x
    sudo apt update
    sudo apt -y install wamerican wamerican-large wamerican-huge wamerican-insane jq curl
    set +x
fi

# Fetch the words javascript and turn them into a file we can search.
if [ ! -f "$wordle_words_file" ] || [ ! -f "$wordle_words_js" ] || [ $(($(date +%s) - $(stat --format='%Z' "$wordle_words_js"))) -gt 1800 ]; then
    curl -L -f -sS -o "$wordle_words_js" --time-cond "$wordle_words_js" "$wordle_words_url"
    cat "$wordle_words_js" | egrep -o "JSON.parse\('\[[^)]+\]'\)"  | sed -e "s/^JSON.parse('//" -e "s/')//" | jq .[] | sed 's/"//g' > "$wordle_words_file"
fi

# Input handling (TODO: Improve this)
# - character position string:
#   a series of periods that are replaced with the letter in that slot
#   the number of dots determines the length of the word to look for
# - included but wrong position characters: just a sequence of characters that should be included
# - excluded characters: a string of characters that should not be included

char_pos_str="${1:-}"
included_chars="${2:-}"
excluded_chars="${3:-}"

if ! echo "$char_pos_str" | egrep -q -i '^[a-z.]{4,11}$'; then
    echo "ERROR: Invalid character position string input." >&2
    exit 1
fi
char_pos_str=$(echo "$char_pos_str" | tr A-Z a-z)

if ! echo "$included_chars" | egrep -q -i '^([a-z]*)|(\[[a-z]+\])$'; then
    echo "ERROR: Invalid included characters string input." >&2
    exit 1
fi
# Add the "right letter right position" characters to the included_chars set.
included_chars+=$(echo "$char_pos_str" | sed 's/[.]//g')
included_chars=$(echo $(echo "$included_chars" | tr A-Z a-z | sed -r -e 's/^\[//' -e 's/\]([a-z]*)$/\1/' | sed -r -e 's/(.)/\1\n/g' | egrep '^[a-z]+$' | sort) | sed 's/ //g')
if [ -z "$included_chars" ] && ! echo "$char_pos_str" | grep -q -i '[a-z]'; then
    included_chars=$(echo {a..z} | sed 's/ //g')
fi

if ! echo "$excluded_chars" | egrep -q -i '^([a-z]*)|(\[^[a-z]+\])$'; then
    echo "ERROR: Invalid included characters string input." >&2
    exit 1
fi
excluded_chars=$(echo $(echo "$excluded_chars" | tr A-Z a-z | sed -e 's/^\[^//' -e 's/\]$//' | sed -r -e 's/(.)/\1\n/g' | egrep '^[a-z]+$' | sort) | sed 's/ //g')
if [ -z "$excluded_chars" ]; then
    excluded_chars='@'
fi

# Check to see if included_chars and excluded_chars overlap at all (input error)
if join -i <(echo "$included_chars" | sed -r 's/(.)/\1\n/g' | sort) <(echo "$excluded_chars" | sed -r 's/(.)/\1\n/g' | sort) | grep '^[a-z]$'; then
    echo "ERROR: included_chars and excluded_chars overlap." >&2
    exit 1
fi

function is_first_guess() {
    #[ -z "$included_chars" ] && [ -z "$excluded_chars" ] && ! echo "$char_pos_str" | grep -q '[a-z]'
    ! echo "$char_pos_str" | grep -q '[a-z]'
}

function remove_duplicate_letter_words() {
    egrep -v '(.).*\1'
}

function opt_remove_duplicate_letter_words() {
    if is_first_guess; then
        remove_duplicate_letter_words
    else
        cat
    fi
}

function search_wordset() {
    local re="$1"

    included_chars_regexp=''
    if [ -n "$included_chars" ]; then
        included_chars_regexp="[$included_chars]"
    else
        included_chars_regexp='.*'
    fi

    excluded_chars_regexp=''
    if [ -n "$excluded_chars" ]; then
        excluded_chars_regexp="[$excluded_chars]"
    else
        # We're searching English words, so there shouldn't be any special characters like this.
        excluded_chars_regexp='[@]'
    fi

    if $use_sysdict_words_file; then
        egrep -x "$re" "$wordle_words_file" "$sysdict_words_file" | cut -d: -f2
    else
        egrep -x "$re" "$wordle_words_file"
    fi  | grep "$included_chars_regexp" \
        | grep -v "$excluded_chars_regexp" \
        | opt_remove_duplicate_letter_words \
        | sort | uniq
}

# Construct a regexp to search in the word list for.
regexp=''
# For the initial guess construct a character class using letter frequencies and the dictionaries.
# See Also: https://www3.nd.edu/~busiforc/handouts/cryptography/Letter%20Frequencies.html
frequent_letters='etaoinshrdlcumwfgypbvkjxqz'
frequent_letters_cnt=$(echo -n "$frequent_letters" | wc -c)
str_len=$(echo -n "$char_pos_str" | wc -c)
if is_first_guess; then
    word=''
    for i in $(seq $str_len $frequent_letters_cnt); do
        chars=$(echo "$frequent_letters" | cut -c-$i)
        regexp="[$chars]{$str_len}"
        set +o pipefail
        word=$(search_wordset "$regexp" | opt_remove_duplicate_letter_words | head -n1)
        set -o pipefail
        if [ -n "$word" ]; then
            # found at least one matching frequent word in the wordset
            break
        fi
        # else keep allowing more letters until we find one
    done
else
    # TODO: currently we are throwing information away about included_chars that
    # should not be in certain position.

    # Generate a character class expression.
    chars=$(echo {a..z} | sed 's/ /\n/g')
    if [ -n "$excluded_chars" ]; then
        chars=$(echo "$chars" | grep -v "^[$excluded_chars]$")
    fi
    # flatten it again
    chars=$(echo $(echo $chars) | sed 's/ //g')
    charcls="[$chars]"

    #regexp=$(echo "$char_pos_str" | sed "s/[.]/$charcls/g")

    regexp="$char_pos_str"
fi

words=$(search_wordset "$regexp" || true)
words_without_repeat_letters=$(echo "$words" | remove_duplicate_letter_words)
if [ -z "$words" ]; then
    echo 'Failed to find any potential matches!' >&2
    exit 1
fi

# TODO: sort the output next tries by letter, digram, trigram, begging, ending frequencies?

# refine the list using some simple letter frequency checks
# iteratively remove less common letters
if is_first_guess; then
    included_chars_cls='[@]'
else
    included_chars_cls="[$included_chars]"
fi
for i in $(seq 1 $frequent_letters_cnt); do
    chars=$(echo "$frequent_letters" | sed -e "s/[$included_chars_cls]//g" | rev | cut -c-$i)
    new_words=$(echo "$words" | grep -v "[$chars]" || true)
    new_words_without_repeat_letters=$(echo "$words_without_repeat_letters" | grep -v "[$chars]" || true)
    if echo "$new_words_without_repeat_letters" | grep -q '[a-z]'; then
        words_without_repeat_letters="$new_words_without_repeat_letters"
    fi

    if echo "$new_words" | grep -q '[a-z]'; then
        words="$new_words"
        #echo "continuing reduction after $i of $chars: $words"
    else
        #echo "stopping after $i"
        break
    fi
done

echo "Possible match suggestions without repeat letters (better for early guesses):"
echo
echo "$words_without_repeat_letters"
echo
echo "Possible match suggestions:"
echo
echo "$words"

#!/bin/bash
# wordle-solver.sh
# bpkroth
# 2022-01-18

set -eu
set -o pipefail

scriptdir=$(dirname $(readlink -f $0))
cd "$scriptdir"

use_sysdict_words_file=true

# Pick a system dictionary to use.
#sysdict_words_file='/usr/share/dict/words'
sysdict_words_file='/usr/share/dict/american-english'
#sysdict_words_file='/usr/share/dict/american-english-large'
#sysdict_words_file='/usr/share/dict/american-english-huge'
#sysdict_words_file='/usr/share/dict/american-english-insane'

wordle_words_file='wordle_words.txt'
wordle_words_url='https://wordlegame.org/assets/js/wordle/en.js?v4'
wordle_words_js='wordle.js'
wordle_words_js_ts='.wordle.js.checked'

# Install some dependencies in case they're missing.
if [ ! -f "$sysdict_words_file" ] || ! type jq curl >/dev/null; then
    set -x
    sudo apt update
    sudo apt -y install wamerican wamerican-large wamerican-huge wamerican-insane jq curl
    set +x
fi

# Fetch the words javascript and turn them into a file we can search.
if [ ! -s "$wordle_words_file" ] || [ ! -s "$wordle_words_js" ] || [ ! -f "$wordle_words_js_ts" ] || [ $(($(date +%s) - $(stat --format='%Y' "$wordle_words_js_ts"))) -gt 1800 ]; then
    echo "INFO: Updating local wordle dictionary." >&2
    curl -L -f -sS -o "$wordle_words_js" --time-cond "$wordle_words_js" "$wordle_words_url"
    touch "$wordle_words_js_ts"
    rm -f "$wordle_words_file"
    # Remove unicode escape characters that jq doesn't understand.
    cat "$wordle_words_js" | egrep -o "JSON.parse\('\[[^)]+\]'\)"  | sed -e "s/^JSON.parse('//" -e "s/')//" | sed -e 's/,/,\n/g' | grep -v '\\x' | jq .[] | sed 's/"//g' > "$wordle_words_file"
fi

# Input handling
# - character position string:
#   a series of periods that are replaced with the letter in that slot
#   the number of dots determines the length of the word to look for
# - all remaining arguments are of the form guess:result where
#   guess is a word (of the same length as the character position string), and
#   result is a dot delimited string of "right letters (though possibly wrong spot)"
# e.g. ......s ethnos:.t.n.s trains:t..ins

# DONE: Improve this to replace the first arg with a length number and then use
# captial letters to construct the char_pos_str with the remaining args.

char_str_len="${1:-}"
if ! echo "$char_str_len" | egrep -q '^[0-9]+'; then
    echo "ERROR: Invalid character length." >&2
    exit 1
fi
shift

is_first_guess=''
if [ $# -eq 0 ]; then
    is_first_guess=true
else
    is_first_guess=false
fi

# The set of characters we know must be included.
included_chars=''

function remove_duplicate_letter_words() {
    egrep -v '(.).*\1' || true
}

function opt_remove_duplicate_letter_words() {
    if $is_first_guess; then
        remove_duplicate_letter_words
    else
        cat
    fi
}

function search_wordset() {
    local re="$1"

    included_chars_awk='1'   # awk's true
    if [ -n "$included_chars" ] && ! $is_first_guess; then
        # compose a boolean "line matches all characters" check
        included_chars_awk+=$(echo "$included_chars" | sed -r -e 's|([a-z])| \&\& /\1/|g')
    fi

    if $use_sysdict_words_file; then
        #egrep -x "$re" "$wordle_words_file" "$sysdict_words_file" | cut -d: -f2
        egrep -x "$re" "$wordle_words_file" || egrep -x "$re" "$sysdict_words_file"
    else
        egrep -x "$re" "$wordle_words_file"
    fi  | awk "( $included_chars_awk ) { print }" \
        | sort | uniq
}

# Construct a regexp to search in the word list for.
regexp=''
# For the initial guess construct a character class using letter frequencies and the dictionaries.
# See Also: https://www3.nd.edu/~busiforc/handouts/cryptography/Letter%20Frequencies.html
frequent_letters='etaoinshrdlcumwfgypbvkjxqz'
frequent_letters_cnt=$(echo -n "$frequent_letters" | wc -c)
all_chars=$(echo {a..z} | sed 's/ //g')
if $is_first_guess; then
    #included_chars="$all_chars"
    word=''
    for i in $(seq $char_str_len $frequent_letters_cnt); do
        chars=$(echo "$frequent_letters" | cut -c-$i)
        regexp="[$chars]{$char_str_len}"
        set +o pipefail
        word=$(search_wordset "$regexp" | remove_duplicate_letter_words | head -n1)
        set -o pipefail
        if [ -n "$word" ]; then
            # found at least one matching frequent word in the wordset
            break
        fi
        # else keep allowing more letters until we find one
    done
else
    # construct our old char_pos_str on the fly for easier iteration on cli args
    char_pos_str=$(seq -s' ' 1 $char_str_len | sed -r -e 's/[0-9]+/./g' | sed -e 's/ //g')
    for guess_result_str in $*; do
        if ! echo "$guess_result_str" | egrep -q -i "^[a-z]{$char_str_len}:[a-z.]{$char_str_len}$"; then
            echo "ERROR: Invalid guess:result string format." >&2
            exit 1
        fi
        guess=$(echo "$guess_result_str" | cut -d: -f1)
        result=$(echo "$guess_result_str" | cut -d: -f2)

        #echo "guess_result_str=$guess_result_str" >&2
        for i in $(seq 0 $(($char_str_len-1))); do
            if [[ ${result:$i:1} =~ [A-Z] ]]; then
                if [ ${char_pos_str:$i:1} == '.' ]; then
                    # Replace the i-th dot with the fixed letter.
                    char_pos_str=${char_pos_str:0:$i}${result:$i:1}${char_pos_str:$(($i+1))}
                elif [ ${char_pos_str:$i:1} != ${result:$i:1} ]; then
                    # Check for argument errors.
                    echo "ERROR: Inconsistent character matches at position $i: ${char_pos_str:$i:1} != ${result:$i:1}"
                    exit 1
                fi
            fi
        done
    done
    char_pos_str=$(echo $char_pos_str | tr A-Z a-z)

    # prep some arrays and regex to use for matching word candidates
    # let '@' be a special character denoting an already fixed position
    char_pos_excluded=($(echo "$char_pos_str" | sed -r -e 's/(.)/\1\n/g' | sed 's/[a-z]/@/g'))
    for i in $(seq 0 $(($char_str_len-1))); do
        if [ ${char_pos_excluded[$i]:0:1} == '.' ]; then
            # Cleanup original stub character.
            char_pos_excluded[$i]=''
        fi
    done

    included_chars=''

    for guess_result_str in $*; do
        guess=$(echo "$guess_result_str" | cut -d: -f1 | tr A-Z a-z)
        result=$(echo "$guess_result_str" | cut -d: -f2 | tr A-Z a-z)

        #echo "guess_result_str=$guess_result_str" >&2

        for i in $(seq 0 $(($char_str_len-1))); do
            # check whether that letter was a success, if not, add it to every other free position's excluded set
            if [ "${result:$i:1}" == '.' ]; then
                for j in $(seq 0 $(($char_str_len-1))); do
                    if [ "${char_pos_excluded[$j]}" != '@' ] && ! [[ "${char_pos_excluded[$j]}" =~ "${guess:$i:1}" ]]; then
                        # Append the wrongly guessed character to the excluded characters set for that position.
                        char_pos_excluded[$j]+="${guess:$i:1}"
                    fi
                done
            else
                if ! [[ "$included_chars" =~ "${result:$i:1}" ]]; then
                    included_chars+="${result:$i:1}"
                fi

                if [ "${char_pos_str:$i:1}" == '.' ]; then # || [ "${char_pos_str:$i:1}" != "${result:$i:1}" ]; then
                    # this is the wrong position for that character, append it
                    # to the exclude list, but just for this position
                    char_pos_excluded[$i]+="${result:$i:1}"
                fi
            fi
        done

        #for i in $(seq 0 $(($char_str_len-1))); do echo "char_pos_excluded[$i]=${char_pos_excluded[$i]}" >&2; done
    done

    # turn those character exclusion sets into a regex
    regexp=''
    for i in $(seq 0 $(($char_str_len-1))); do
        # Generate a character class expression.
        if [ "${char_pos_excluded[$i]}" != '@' ] && [ "${char_pos_str:$i:1}" == '.' ]; then
            chars=$(echo "$all_chars" | sed "s/[${char_pos_excluded[$i]}]//g")
        elif [ "${char_pos_excluded[$i]}" == '@' ] && [ "${char_pos_str:$i:1}" != '.' ]; then
            chars="${char_pos_str:$i:1}"
        else
            echo "ERROR" >&2
            exit 1
        fi
        # Add it to the regexp.
        regexp+="[$chars]"
    done
    #echo "regexp=$regexp" >&2
fi

words=$(search_wordset "$regexp" || true)
words_without_repeat_letters=$(echo "$words" | remove_duplicate_letter_words)
if [ -z "$words" ]; then
    echo 'Failed to find any potential matches!' >&2
    exit 1
fi

# TODO: refine or sort the output next tries by letter, digram, trigram, begging, ending frequencies?
if true; then
    max_words=10

    # refine the list using some simple letter frequency checks
    # iteratively remove less common letters
    if $is_first_guess; then
        included_chars_cls='[@]'
    else
        included_chars_cls="[$included_chars]"
    fi
    for i in $(seq 1 $frequent_letters_cnt); do
        chars=$(echo "$frequent_letters" | sed -e "s/[$included_chars_cls]//g" | rev | cut -c-$i)
        new_words=$(echo "$words" | grep -v "[$chars]" || true)
        new_words_without_repeat_letters=$(echo "$words_without_repeat_letters" | grep -v "[$chars]" || true)
        if echo "$new_words_without_repeat_letters" | grep -q '[a-z]'; then
            if [ $(echo "$words_without_repeat_letters" | wc -l) -gt $max_words ]; then
                words_without_repeat_letters="$new_words_without_repeat_letters"
            fi
        fi

        if echo "$new_words" | grep -q '[a-z]'; then
            if [ $(echo "$words" | wc -l) -gt $max_words ]; then
                words="$new_words"
            fi
            #echo "continuing reduction after $i of $chars: $words"
        else
            #echo "stopping after $i"
            break
        fi
    done
fi

echo "=== Possible match suggestions without repeat letters (better for early guesses) ==="
echo
echo "$words_without_repeat_letters"
echo
echo "=== Possible match suggestions with repeat letters ==="
echo
echo "$words" | egrep '(.).*\1'

# wordle-solver

## Usage

```sh
./wordle-solver.sh <dot-delimited-character-position-string> <included-characters> <excluded-characters>
```

1. Start with an initial guess.

    ```sh
    ./wordle-solver.sh ......    # 6 dots for a wordle puzzle of length 6

    Possible match suggestions without repeat letters (better for early guesses):

    ethnos
    hasten
    honest
    shanti
    thanes

    Possible match suggestions:

    ethnos
    hasten
    honest
    shanti
    thanes
    ```

    Input: "ethnos"

    Returns:
    - S is correct.
    - T and N are included but in the wrong spot.

2. Next guess.

    ```sh
    ./wordle-solver.sh .....s tn eho
    Possible match suggestions without repeat letters (better for early guesses):

    trains

    Possible match suggestions:

    saints
    satins
    stains
    stasis
    stints
    taints
    titans
    ```

    Input: "trains"

    Returns:
    - S is correct
    - T, I, and N are include but in the wrong spot.

3. and so on ...

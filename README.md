# wordle-solver

## Usage

```sh
./wordle-solver.sh <dot-delimited-character-position-string> [<guess-string:dot-delimited-result-string>]*
```

1. Start with an initial guess.

    ```sh
    ./wordle-solver.sh .....
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

    Input: "atone"

    Returns:
    - e is included but in the wrong spot.

2. Next guess.

    ```sh
    ./wordle-solver.sh ..... atone:....e
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

3. Next guess.
    ```sh
    ./wordle-solver.sh ....s atone:....e heirs:.e..S
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

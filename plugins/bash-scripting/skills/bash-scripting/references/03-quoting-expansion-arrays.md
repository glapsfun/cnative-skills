# Quoting, expansion, arrays, and tests

## Quoting is the foundation

Unquoted expansions undergo **word-splitting** (on `IFS`) and **pathname expansion** (globbing). That means a single variable holding `my file.txt` becomes two arguments, and one holding `*` expands to every file in the directory. Quoting disables both.

```bash
file="my report.txt"
rm $file       # WRONG: rm 'my' 'report.txt' — two files, neither yours
rm "$file"     # RIGHT: rm 'my report.txt'
```

Rules of thumb:

- Quote every expansion by default: `"$var"`, `"${arr[@]}"`, `"$(cmd)"`, `"$@"`.
- Forward all arguments with `"$@"` (each arg preserved). `"$*"` joins them into one string — only use it when you actually want that.
- The only routine places you *omit* quotes: inside `[[ ]]` for the left operand (it doesn't split), and when you deliberately want glob/split behavior.
- Use `${var}` braces when the name touches adjacent text (`"${prefix}_suffix"`) or to disambiguate; otherwise plain `"$var"` is fine.

## Parameter expansion (string ops without external tools)

Bash can slice and reshape strings natively — faster and safer than shelling out to `sed`/`cut`.

```bash
${var:-default}     # value, or "default" if unset/empty
${var:=default}     # value, or assign and use "default" if unset/empty
${var:?message}     # value, or error with "message" and exit if unset/empty
${var:+alt}         # "alt" only if var is set/non-empty (else empty)

${#var}             # length
${var:offset:len}   # substring

${var#pattern}      # remove shortest leading match (e.g. ${path##*/} = basename)
${var##pattern}     # remove longest leading match
${var%pattern}      # remove shortest trailing match (e.g. ${file%.*} = drop extension)
${var%%pattern}     # remove longest trailing match

${var/old/new}      # replace first occurrence
${var//old/new}     # replace all occurrences
${var/#old/new}     # replace if at start
${var/%old/new}     # replace if at end
```

Bash 4+ case conversion (not in bash 3.2 / macOS default bash):

```bash
${var^^}            # uppercase all
${var,,}            # lowercase all
${var^}             # uppercase first char
```

`${path##*/}` and `${path%/*}` are pure-shell `basename`/`dirname` — handy, but note they don't normalize trailing slashes the way the real tools do.

## Arrays

Arrays are how you hold lists of values (especially command arguments) without word-splitting bugs. They are a bash feature — unavailable in POSIX `sh`.

```bash
declare -a files=( "a.txt" "b c.txt" )
files+=( "d.txt" )                 # append

echo "${files[@]}"                 # all elements, each quoted separately
echo "${#files[@]}"                # count
echo "${files[0]}"                 # first element
echo "${!files[@]}"                # indices

for f in "${files[@]}"; do …; done # iterate safely

# Build up command arguments conditionally — the right way to make flags optional.
args=( --color=auto )
(( verbose )) && args+=( --verbose )
grep "${args[@]}" "${pattern}" "${file}"
```

Associative arrays (maps), bash 4+:

```bash
declare -A count
count["apple"]=3
count["pear"]=1
for key in "${!count[@]}"; do
  printf '%s=%s\n' "${key}" "${count[$key]}"
done
```

Read command output into an array safely with `mapfile` (bash 4+):

```bash
mapfile -t lines < "${file}"           # one element per line, no trailing newline
mapfile -t -d '' paths < <(find . -print0)   # NUL-delimited, fully safe
```

`"${array[@]}"` is to lists what `"$var"` is to scalars: the quoted form that preserves each element exactly.

## Tests: `[[ ]]` vs `[ ]`

In bash, prefer `[[ ]]`: it doesn't word-split or glob its operands, supports `&&`/`||`, pattern matching, and `=~` regex.

```bash
[[ -f "${file}" ]]              # regular file exists
[[ -d "${dir}" ]]              # directory exists
[[ -e "${path}" ]]             # exists (any type)
[[ -r "${f}" && -w "${f}" ]]   # readable and writable
[[ -z "${s}" ]]                # empty string
[[ -n "${s}" ]]                # non-empty string
[[ "${a}" == "${b}" ]]         # string equality (== or =)
[[ "${a}" == prefix* ]]        # glob pattern match (do NOT quote the pattern)
[[ "${a}" =~ ^[0-9]+$ ]]       # regex match; captures in ${BASH_REMATCH[@]}

# Numeric comparison: use (( )) arithmetic context, not string operators.
(( count > 5 ))
(( a == b ))
[[ "${n}" -gt 5 ]]             # also valid inside [[ ]]
```

Gotcha: in a `[[ str == pattern ]]`, quoting the right-hand side turns the pattern into a literal. `[[ "$x" == *.txt ]]` matches a suffix; `[[ "$x" == "*.txt" ]]` matches the literal string `*.txt`. Same for `=~` — quote a regex and it becomes literal.

Use `(( ))` for all arithmetic — it's cleaner than `[ "$a" -lt "$b" ]` and supports C-style operators (`+= ++ * / %`, ternary).

## Command substitution and here-docs

```bash
now="$(date +%s)"               # $(...) nests cleanly; never use backticks
```

Heredocs feed multi-line input to a command:

```bash
cat <<EOF                        # unquoted EOF: variables/$(...) are expanded
Hello ${USER}, today is $(date +%F).
EOF

cat <<'EOF'                      # quoted 'EOF': literal, nothing expanded
This $variable is printed verbatim.
EOF

cat <<-EOF                       # <<- strips leading TABS (not spaces) for indentation
	indented in source, flush in output
EOF
```

Quote the delimiter (`<<'EOF'`) whenever the body should be literal — config templates, embedded scripts — to avoid surprise expansion.

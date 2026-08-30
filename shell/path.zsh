# Homebrew. Apple Silicon installs to /opt/homebrew, Intel to /usr/local.
# Checked directly rather than shelled out to, so a new shell stays fast.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Keg-only formulae. Homebrew installs these but deliberately does not link them
# into PATH, so without this java, sqlite3 and psql would not exist as commands.
typeset -U path PATH
if [[ -n ${HOMEBREW_PREFIX:-} ]]; then
  for _ms_dir in openjdk sqlite postgresql@17; do
    [[ -d $HOMEBREW_PREFIX/opt/$_ms_dir/bin ]] && path=("$HOMEBREW_PREFIX/opt/$_ms_dir/bin" $path)
  done
  unset _ms_dir

  _ms_java=$HOMEBREW_PREFIX/opt/openjdk/libexec/openjdk.jdk/Contents/Home
  [[ -d $_ms_java ]] && export JAVA_HOME=$_ms_java
  unset _ms_java
fi

# Prompt.
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

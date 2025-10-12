# FILES

_\$XDG_CONFIG_HOME/ghostty/config.ghostty_

: Location of the default configuration file.

_\$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty_

: **On macOS**, location of the default configuration file. This location takes
precedence over the XDG environment locations.

_\$LOCALAPPDATA/ghostty/config.ghostty_

: **On Windows**, if _\$XDG_CONFIG_HOME_ is not set, _\$LOCALAPPDATA_ will be searched
for configuration files.

# ENVIRONMENT

**XDG_CONFIG_HOME**

: Default location for configuration files.

**$HOME/Library/Application Support/com.mitchellh.ghostty**

: **MACOS ONLY** default location for configuration files. This location takes
precedence over the XDG environment locations.

**LOCALAPPDATA**

: **WINDOWS ONLY:** alternate location to search for configuration files.

# BUGS

See GitHub issues: <https://github.com/ghostty-org/ghostty/issues>

# AUTHOR

Mitchell Hashimoto <m@mitchellh.com>
Ghostty contributors <https://github.com/ghostty-org/ghostty/graphs/contributors>

# SEE ALSO

**ghostty(1)**

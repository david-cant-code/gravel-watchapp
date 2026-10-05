"""Stand-in for freetype-py, which the Pebble SDK imports on every build but uses only for font resources."""


def __getattr__(name):
    raise RuntimeError("font resources are not supported: this build does not install freetype-py")

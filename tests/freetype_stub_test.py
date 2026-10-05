"""The freetype stand-in imports cleanly, as the SDK's build needs, and refuses any real use."""
import sys

import freetype

if not freetype.__file__.endswith("tools/stubs/freetype/__init__.py"):
    sys.exit("imported a real freetype, not the stand-in: " + freetype.__file__)
try:
    freetype.Face("font.ttf")
except RuntimeError:
    print("freetype stand-in test passed")
else:
    sys.exit("the freetype stand-in allowed a font to load")

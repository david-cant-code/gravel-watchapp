import os

top = '.'
out = 'build'


def options(ctx):
    ctx.load('pebble_sdk')


def configure(ctx):
    ctx.load('pebble_sdk')

    # Same source, same PBW: the SDK would stamp the build's time into the app and its bundle (sdk-core 4.33.1
    # pebble_sdk_common.configure) and, through -g, the checkout's path into what --build-id hashes
    # (pebble_sdk_gcc.configure). Each platform's environment keeps its own CFLAGS, so each one is set.
    try:
        timestamp = int(os.environ['SOURCE_DATE_EPOCH'])
    except (KeyError, ValueError):
        ctx.fatal('SOURCE_DATE_EPOCH is not set to a number; build with tools/build.sh')
    prefix_map = '-ffile-prefix-map={}=.'.format(ctx.path.abspath())
    for env in [ctx.env] + [ctx.all_envs[platform] for platform in ctx.env.TARGET_PLATFORMS]:
        env.TIMESTAMP = timestamp
        env.append_value('CFLAGS', [prefix_map])


def store_pngs_uncompressed():
    """The SDK re-encodes PNG resources at zlib level 9 (sdk-core 4.33.1 common/tools/png2pblpng.py,
    _convert_png_to_pebble_png_writer), whose output differed between a zlib and a zlib-ng build machine; level 0
    stores the image data instead."""
    import png

    init = png.Writer.__init__

    def init_stored(self, *args, **kwargs):
        kwargs['compression'] = 0
        init(self, *args, **kwargs)

    png.Writer.__init__ = init_stored


def build(ctx):
    ctx.load('pebble_sdk')
    store_pngs_uncompressed()

    binaries = []
    cached_env = ctx.env
    for platform in ctx.env.TARGET_PLATFORMS:
        ctx.env = ctx.all_envs[platform]
        ctx.set_group(ctx.env.PLATFORM_NAME)
        app_elf = '{}/pebble-app.elf'.format(ctx.env.BUILD_DIR)
        ctx.pbl_build(source=ctx.path.ant_glob('src/c/**/*.c'), target=app_elf, bin_type='app')
        binaries.append({'platform': platform, 'app_elf': app_elf})
    ctx.env = cached_env

    ctx.set_group('bundle')
    ctx.pbl_bundle(binaries=binaries, js=[])

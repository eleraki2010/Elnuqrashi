import os
from PIL import Image

def generate_icons():
    src_path = os.path.join('assets', 'images', 'logo.png')
    if not os.path.exists(src_path):
        print(f"File not found: {src_path}")
        return

    img = Image.open(src_path).convert('RGBA')

    # 1. Windows ICO
    win_ico_path = os.path.join('windows', 'runner', 'resources', 'app_icon.ico')
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    img.save(win_ico_path, format='ICO', sizes=ico_sizes)
    print(f"Updated Windows icon: {win_ico_path}")

    # 2. Android Mipmaps
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    for folder, size in android_sizes.items():
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        out_path = os.path.join('android', 'app', 'src', 'main', 'res', folder, 'ic_launcher.png')
        if os.path.exists(os.path.dirname(out_path)):
            resized.save(out_path, format='PNG')
            print(f"Updated Android icon: {out_path}")

    # 3. Web Favicon & Icons
    if os.path.exists('web'):
        img.resize((32, 32), Image.Resampling.LANCZOS).save(os.path.join('web', 'favicon.png'), format='PNG')
        icons_dir = os.path.join('web', 'icons')
        if os.path.exists(icons_dir):
            img.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, 'Icon-192.png'), format='PNG')
            img.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, 'Icon-512.png'), format='PNG')
        print("Updated Web icons")

if __name__ == '__main__':
    generate_icons()

"""Draw the MathMentor launcher icon: + - x / operators on the app's blue."""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

BLUE = (21, 101, 192, 255)  # AppColors.primary
AMBER = (255, 160, 0, 255)  # AppColors.secondary
WHITE = (255, 255, 255, 255)
S = 1024


def operators(draw: ImageDraw.ImageDraw, cx: float, cy: float, size: float) -> None:
    """2x2 grid of operators centred on (cx, cy); `size` = whole grid width."""
    cell = size / 2
    t = size * 0.075  # stroke thickness
    arm = cell * 0.30  # half-length of a stroke
    r = t / 2

    def bar(x0, y0, x1, y1, fill):
        draw.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=fill)

    centres = [
        (cx - cell / 2, cy - cell / 2),
        (cx + cell / 2, cy - cell / 2),
        (cx - cell / 2, cy + cell / 2),
        (cx + cell / 2, cy + cell / 2),
    ]
    # plus (amber)
    x, y = centres[0]
    bar(x - arm, y - t / 2, x + arm, y + t / 2, AMBER)
    bar(x - t / 2, y - arm, x + t / 2, y + arm, AMBER)
    # minus
    x, y = centres[1]
    bar(x - arm, y - t / 2, x + arm, y + t / 2, WHITE)
    # times: two rotated bars, drawn on a temp layer
    x, y = centres[2]
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.rounded_rectangle((x - arm, y - t / 2, x + arm, y + t / 2), radius=r, fill=WHITE)
    ld.rounded_rectangle((x - t / 2, y - arm, x + t / 2, y + arm), radius=r, fill=WHITE)
    layer = layer.rotate(45, center=(x, y), resample=Image.BICUBIC)
    draw._image.alpha_composite(layer)  # noqa: SLF001
    # divide (amber)
    x, y = centres[3]
    bar(x - arm, y - t / 2, x + arm, y + t / 2, AMBER)
    d = t * 1.1
    for dy in (-arm * 0.62, arm * 0.62):
        draw.ellipse((x - d / 2, y + dy - d / 2, x + d / 2, y + dy + d / 2), fill=AMBER)


def main(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # Legacy icon: full-bleed rounded blue square with the operators.
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(icon)
    d.rounded_rectangle((0, 0, S - 1, S - 1), radius=S * 0.22, fill=BLUE)
    operators(d, S / 2, S / 2, S * 0.70)
    icon.save(out_dir / "app_icon.png")

    # Adaptive foreground: transparent, operators inside the 66% safe zone.
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    operators(ImageDraw.Draw(fg), S / 2, S / 2, S * 0.50)
    fg.save(out_dir / "app_icon_foreground.png")


if __name__ == "__main__":
    main(Path(sys.argv[1]))

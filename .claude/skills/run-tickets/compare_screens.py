"""Capture mock screens and put each beside the app's screenshot.

uv run --with playwright --with pillow python3 compare_screens.py <mock.html> <shots-dir> <id>...

For each screen id (as the mock labels it, such as L2c or 07b), this saves
<shots-dir>/<id>-mock.png. When <shots-dir>/<id>-app.png exists, it also saves
<shots-dir>/<id>.png with the app on the left and the mock on the right.
"""

import pathlib
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

SCALE = 3
GAP = 48


def capture_mock(mock: pathlib.Path, out: pathlib.Path, ids: list[str]) -> list[str]:
    missing = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=SCALE)
        page.goto(mock.resolve().as_uri())
        page.wait_for_load_state("networkidle")
        page.evaluate("document.fonts.ready")
        for screen_id in ids:
            cell = page.locator(".cell").filter(
                has=page.locator(".cell-title span:first-child", has_text=screen_id)
            )
            exact = [c for c in cell.all() if c.locator(".cell-title span").first.inner_text() == screen_id]
            if not exact:
                missing.append(screen_id)
                continue
            exact[0].locator(".screen").first.screenshot(path=out / f"{screen_id}-mock.png")
        browser.close()
    return missing


def pair(out: pathlib.Path, screen_id: str) -> bool:
    app_path = out / f"{screen_id}-app.png"
    if not app_path.exists():
        return False
    app = Image.open(app_path).convert("RGB")
    mock = Image.open(out / f"{screen_id}-mock.png").convert("RGB")
    height = max(app.height, mock.height)
    app = app.resize((round(app.width * height / app.height), height))
    mock = mock.resize((round(mock.width * height / mock.height), height))
    both = Image.new("RGB", (app.width + GAP + mock.width, height), "white")
    both.paste(app, (0, 0))
    both.paste(mock, (app.width + GAP, 0))
    both.save(out / f"{screen_id}.png")
    return True


def main() -> None:
    mock, out, ids = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3:]
    out.mkdir(parents=True, exist_ok=True)
    missing = capture_mock(mock, out, ids)
    for screen_id in ids:
        if screen_id in missing:
            print(f"{screen_id}: not in the mock")
        elif pair(out, screen_id):
            print(f"{screen_id}: {out / f'{screen_id}.png'}")
        else:
            print(f"{screen_id}: mock only, {out / f'{screen_id}-mock.png'}")


if __name__ == "__main__":
    main()

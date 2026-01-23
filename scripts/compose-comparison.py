#!/usr/bin/env python3
"""
Compose Visual Comparison Image

Creates a labeled side-by-side comparison image showing:
- Reference (EPUB.js)
- iOS HTML (WebView) renderer
- iOS Native renderer

Usage:
    uv run --with pillow scripts/compose-comparison.py <book> <chapter>
    uv run --with pillow scripts/compose-comparison.py frankenstein 1

Output:
    /tmp/reader-tests/comparison_<book>_ch<chapter>.png
"""

import argparse
import sys
from pathlib import Path


def compose_comparison(book: str, chapter: str, output_dir: str = "/tmp/reader-tests") -> str:
    """Compose a labeled side-by-side comparison image."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Error: Pillow not installed. Run with: uv run --with pillow", file=sys.stderr)
        sys.exit(1)

    output_path = Path(output_dir)

    # Expected input paths
    ref_path = output_path / f"ref_{book}_ch{chapter}.png"
    html_path = output_path / f"ios_{book}_ch{chapter}_html.png"
    native_path = output_path / f"ios_{book}_ch{chapter}_native.png"

    # Fallback: if _html doesn't exist, try the regular ios_ screenshot
    if not html_path.exists():
        html_path = output_path / f"ios_{book}_ch{chapter}.png"

    # Check which files exist
    images = []
    labels = []

    if ref_path.exists():
        images.append(Image.open(ref_path))
        labels.append("Reference (EPUB.js)")
    else:
        print(f"Warning: Reference screenshot not found: {ref_path}", file=sys.stderr)

    if html_path.exists():
        images.append(Image.open(html_path))
        labels.append("iOS HTML (WebView)")
    else:
        print(f"Warning: iOS HTML screenshot not found: {html_path}", file=sys.stderr)

    if native_path.exists():
        images.append(Image.open(native_path))
        labels.append("iOS Native")
    else:
        print(f"Note: iOS Native screenshot not found: {native_path}", file=sys.stderr)

    if len(images) < 2:
        print("Error: Need at least 2 images to create comparison", file=sys.stderr)
        sys.exit(1)

    # Configuration
    label_height = 60
    padding = 20
    bg_color = (30, 30, 30)  # Dark gray background
    label_color = (255, 255, 255)  # White text

    # Calculate target height (use the tallest image)
    max_height = max(img.height for img in images)

    # Resize images to have the same height while maintaining aspect ratio
    resized_images = []
    for img in images:
        if img.height != max_height:
            ratio = max_height / img.height
            new_width = int(img.width * ratio)
            img = img.resize((new_width, max_height), Image.Resampling.LANCZOS)
        resized_images.append(img)

    # Calculate total width
    total_width = sum(img.width for img in resized_images) + padding * (len(resized_images) + 1)
    total_height = max_height + label_height + padding * 2

    # Create output image
    output = Image.new('RGB', (total_width, total_height), bg_color)
    draw = ImageDraw.Draw(output)

    # Try to load a nice font, fall back to default
    try:
        # Try common system fonts
        font_paths = [
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/SFNSText.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
        font = None
        for fp in font_paths:
            if Path(fp).exists():
                font = ImageFont.truetype(fp, 32)
                break
        if font is None:
            font = ImageFont.load_default()
    except Exception:
        font = ImageFont.load_default()

    # Paste images and draw labels
    x_offset = padding
    for img, label in zip(resized_images, labels):
        # Paste image
        y_offset = label_height + padding
        output.paste(img, (x_offset, y_offset))

        # Draw label centered above image
        bbox = draw.textbbox((0, 0), label, font=font)
        text_width = bbox[2] - bbox[0]
        text_x = x_offset + (img.width - text_width) // 2
        text_y = padding
        draw.text((text_x, text_y), label, fill=label_color, font=font)

        x_offset += img.width + padding

    # Save output
    output_file = output_path / f"comparison_{book}_ch{chapter}.png"
    output.save(output_file, "PNG")
    print(f"Comparison image saved to: {output_file}")

    return str(output_file)


def main():
    parser = argparse.ArgumentParser(
        description="Compose a labeled side-by-side comparison image"
    )
    parser.add_argument("book", help="Book slug (e.g., frankenstein)")
    parser.add_argument("chapter", help="Chapter number (0-based)")
    parser.add_argument(
        "--output-dir", "-o",
        default="/tmp/reader-tests",
        help="Output directory (default: /tmp/reader-tests)"
    )

    args = parser.parse_args()
    compose_comparison(args.book, args.chapter, args.output_dir)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
LLM-as-Judge Visual Comparison Script

Compares reference screenshots (from EPUB.js reference server) with iOS app screenshots
using Claude to evaluate visual differences and guide deterministic test creation.

Usage:
    uv run scripts/visual-compare.py <reference_image> <ios_image>

Environment:
    ANTHROPIC_API_KEY: Required. Your Anthropic API key.

Output:
    JSON with ratings, priority issues, and suggested tests.
"""

import argparse
import base64
import json
import os
import sys
from pathlib import Path


def encode_image(image_path: str) -> tuple[str, str]:
    """Encode an image file to base64 and determine its media type."""
    path = Path(image_path)

    if not path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    suffix = path.suffix.lower()
    media_types = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }

    media_type = media_types.get(suffix, "image/png")

    with open(path, "rb") as f:
        data = base64.standard_b64encode(f.read()).decode("utf-8")

    return data, media_type


def build_comparison_prompt() -> str:
    """Build the structured prompt for visual comparison."""
    return """You are evaluating the visual rendering quality of an EPUB reader app.

Compare these two screenshots:
1. REFERENCE: The expected rendering from EPUB.js (a well-established EPUB renderer)
2. iOS APP: The rendering from our iOS reader app

Evaluate the iOS app rendering against the reference on these dimensions:

## Evaluation Criteria

1. **Text Content Completeness** (1-5)
   - Is all text from the reference visible?
   - Is text truncated, missing, or duplicated?

2. **Typography** (1-5)
   - Font size relative to reference
   - Line height / leading
   - Letter spacing
   - Font weight accuracy

3. **Layout** (1-5)
   - Margins (left, right, top, bottom)
   - Text alignment (justified, left, centered)
   - Paragraph indentation
   - Column width / line length

4. **Images** (1-5, or N/A if no images)
   - Image placement
   - Image sizing / aspect ratio
   - Image quality

5. **Overall Fidelity** (1-5)
   - How close is the iOS rendering to the reference?

## Response Format

Respond with ONLY valid JSON in this exact format:
```json
{
  "overall": "PASS" | "NEEDS_WORK" | "MAJOR_DIFF",
  "scores": {
    "text_completeness": 1-5,
    "typography": 1-5,
    "layout": 1-5,
    "images": 1-5 | "N/A",
    "overall_fidelity": 1-5
  },
  "priority_issues": [
    "Description of most important issue to fix",
    "Second most important issue"
  ],
  "detailed_observations": {
    "text": "Observations about text rendering",
    "typography": "Observations about typography",
    "layout": "Observations about layout/margins",
    "images": "Observations about images (if any)"
  },
  "suggested_tests": [
    {
      "name": "testMarginWidth",
      "description": "Test that left/right margins are at least 48pt",
      "assertion": "margin >= 48pt"
    }
  ]
}
```

Guidelines for overall rating:
- PASS: Scores average 4+ and no individual score below 3
- NEEDS_WORK: Some scores below 4 but no critical issues
- MAJOR_DIFF: Any score 2 or below, or critical content issues"""


def compare_screenshots(reference_path: str, ios_path: str) -> dict:
    """Send both screenshots to Claude for comparison."""
    try:
        import anthropic
    except ImportError:
        print("Error: anthropic package not installed.", file=sys.stderr)
        print("Install with: uv add anthropic", file=sys.stderr)
        sys.exit(1)

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY environment variable not set.", file=sys.stderr)
        sys.exit(1)

    # Encode images
    ref_data, ref_media = encode_image(reference_path)
    ios_data, ios_media = encode_image(ios_path)

    client = anthropic.Anthropic(api_key=api_key)

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=2000,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "REFERENCE SCREENSHOT (from EPUB.js):"
                    },
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": ref_media,
                            "data": ref_data,
                        }
                    },
                    {
                        "type": "text",
                        "text": "iOS APP SCREENSHOT:"
                    },
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": ios_media,
                            "data": ios_data,
                        }
                    },
                    {
                        "type": "text",
                        "text": build_comparison_prompt()
                    }
                ]
            }
        ]
    )

    # Extract JSON from response
    response_text = message.content[0].text

    # Try to extract JSON from the response
    # Handle cases where Claude wraps it in markdown code blocks
    if "```json" in response_text:
        start = response_text.find("```json") + 7
        end = response_text.find("```", start)
        json_str = response_text[start:end].strip()
    elif "```" in response_text:
        start = response_text.find("```") + 3
        end = response_text.find("```", start)
        json_str = response_text[start:end].strip()
    else:
        json_str = response_text.strip()

    try:
        result = json.loads(json_str)
    except json.JSONDecodeError as e:
        print(f"Warning: Failed to parse JSON response: {e}", file=sys.stderr)
        print(f"Raw response: {response_text}", file=sys.stderr)
        result = {
            "overall": "ERROR",
            "raw_response": response_text,
            "parse_error": str(e)
        }

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Compare reference and iOS screenshots using LLM"
    )
    parser.add_argument(
        "reference",
        help="Path to reference screenshot (from EPUB.js)"
    )
    parser.add_argument(
        "ios",
        help="Path to iOS app screenshot"
    )
    parser.add_argument(
        "--output", "-o",
        help="Output file path (default: stdout)"
    )
    parser.add_argument(
        "--pretty", "-p",
        action="store_true",
        help="Pretty-print JSON output"
    )

    args = parser.parse_args()

    # Validate files exist
    if not os.path.exists(args.reference):
        print(f"Error: Reference image not found: {args.reference}", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(args.ios):
        print(f"Error: iOS image not found: {args.ios}", file=sys.stderr)
        sys.exit(1)

    # Run comparison
    result = compare_screenshots(args.reference, args.ios)

    # Add metadata
    result["_metadata"] = {
        "reference_path": args.reference,
        "ios_path": args.ios,
    }

    # Output
    indent = 2 if args.pretty else None
    json_output = json.dumps(result, indent=indent)

    if args.output:
        with open(args.output, "w") as f:
            f.write(json_output)
        print(f"Results written to: {args.output}")
    else:
        print(json_output)

    # Exit with appropriate code
    if result.get("overall") == "PASS":
        sys.exit(0)
    elif result.get("overall") == "MAJOR_DIFF":
        sys.exit(2)
    elif result.get("overall") == "ERROR":
        sys.exit(3)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()

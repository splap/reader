#!/usr/bin/env python3
"""
Export BGE tokenizer vocabulary for use in Swift.

Outputs a JSON file with the vocab and special tokens needed
for WordPiece tokenization in the iOS app.
"""

import json
import os

MODEL_NAME = "BAAI/bge-small-en-v1.5"
OUTPUT_PATH = "App/Resources/bge-tokenizer.json"


def export_tokenizer():
    from transformers import AutoTokenizer

    print(f"Loading tokenizer: {MODEL_NAME}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

    # Get vocabulary (word -> id mapping)
    vocab = tokenizer.get_vocab()

    # Get special tokens
    special_tokens = {
        "cls_token": tokenizer.cls_token,
        "cls_token_id": tokenizer.cls_token_id,
        "sep_token": tokenizer.sep_token,
        "sep_token_id": tokenizer.sep_token_id,
        "pad_token": tokenizer.pad_token,
        "pad_token_id": tokenizer.pad_token_id,
        "unk_token": tokenizer.unk_token,
        "unk_token_id": tokenizer.unk_token_id,
        "mask_token": tokenizer.mask_token,
        "mask_token_id": tokenizer.mask_token_id,
    }

    # Create output structure
    output = {
        "vocab": vocab,
        "special_tokens": special_tokens,
        "model_max_length": tokenizer.model_max_length,
        "do_lower_case": tokenizer.do_lower_case if hasattr(tokenizer, 'do_lower_case') else True,
    }

    # Ensure output directory exists
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    # Save
    print(f"Saving tokenizer to {OUTPUT_PATH}")
    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f)

    print(f"Vocabulary size: {len(vocab)}")
    print(f"Special tokens: {special_tokens}")

    # Test tokenization
    test_text = "The quick brown fox jumps over the lazy dog."
    tokens = tokenizer.tokenize(test_text)
    ids = tokenizer.encode(test_text, add_special_tokens=True)
    print(f"\nTest tokenization:")
    print(f"  Input: {test_text}")
    print(f"  Tokens: {tokens}")
    print(f"  IDs: {ids[:10]}... (truncated)")


if __name__ == "__main__":
    try:
        export_tokenizer()
    except ImportError as e:
        print(f"Missing dependency: {e}")
        print("Install with: pip install transformers")
        exit(1)

#!/usr/bin/env python3
"""
Convert BGE-small-en-v1.5 model from HuggingFace to Core ML format.

Uses exporters library for reliable conversion.

Requirements:
    pip install transformers[torch] coremltools exporters

Usage:
    python scripts/convert_bge_to_coreml.py

Output:
    App/Resources/bge-small-en.mlpackage
"""

import os
import sys
import numpy as np

# Model configuration
MODEL_NAME = "BAAI/bge-small-en-v1.5"
OUTPUT_PATH = "App/Resources/bge-small-en.mlpackage"
MAX_SEQ_LENGTH = 512
EMBEDDING_DIM = 384


def convert_with_exporters():
    """Use exporters library for conversion."""
    from exporters.coreml import export
    from transformers import AutoTokenizer

    print(f"Converting model: {MODEL_NAME}")

    # Ensure output directory exists
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    # Export to Core ML using exporters
    export(
        model=MODEL_NAME,
        output=OUTPUT_PATH,
        task="feature-extraction",
        sequence_length=MAX_SEQ_LENGTH,
        compute_units="ALL",  # Use Neural Engine when available
    )

    print(f"Model exported to: {OUTPUT_PATH}")
    return OUTPUT_PATH


def convert_manual():
    """Manual conversion with explicit model wrapping."""
    import torch
    import torch.nn as nn
    import coremltools as ct
    from transformers import AutoModel, AutoTokenizer, AutoConfig

    print(f"Loading model: {MODEL_NAME}")

    config = AutoConfig.from_pretrained(MODEL_NAME)
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    base_model = AutoModel.from_pretrained(MODEL_NAME, config=config)
    base_model.eval()

    print("Model loaded successfully")

    # Create a completely static wrapper
    class StaticBGE(nn.Module):
        def __init__(self, model, seq_len):
            super().__init__()
            # Extract components
            self.word_embeddings = model.embeddings.word_embeddings
            self.position_embeddings = model.embeddings.position_embeddings
            self.token_type_embeddings = model.embeddings.token_type_embeddings
            self.LayerNorm = model.embeddings.LayerNorm
            self.dropout = model.embeddings.dropout
            self.encoder = model.encoder
            self.seq_len = seq_len

            # Pre-compute position IDs as a buffer (static)
            position_ids = torch.arange(seq_len).unsqueeze(0)
            self.register_buffer("position_ids", position_ids)

            # Pre-compute token type IDs (all zeros)
            token_type_ids = torch.zeros(1, seq_len, dtype=torch.long)
            self.register_buffer("token_type_ids", token_type_ids)

        def forward(self, input_ids, attention_mask):
            # Compute embeddings manually with static position IDs
            word_embeds = self.word_embeddings(input_ids)
            position_embeds = self.position_embeddings(self.position_ids)
            token_type_embeds = self.token_type_embeddings(self.token_type_ids)

            embeddings = word_embeds + position_embeds + token_type_embeds
            embeddings = self.LayerNorm(embeddings)
            embeddings = self.dropout(embeddings)

            # Create attention mask for encoder
            extended_mask = attention_mask[:, None, None, :].float()
            extended_mask = (1.0 - extended_mask) * -10000.0

            # Run encoder
            hidden_states = embeddings
            for layer in self.encoder.layer:
                layer_output = layer(hidden_states, extended_mask)
                hidden_states = layer_output[0]

            # Mean pooling
            mask_expanded = attention_mask[:, :, None].float()
            sum_embeddings = (hidden_states * mask_expanded).sum(dim=1)
            sum_mask = mask_expanded.sum(dim=1).clamp(min=1e-9)
            mean_pooled = sum_embeddings / sum_mask

            # L2 normalize
            normalized = nn.functional.normalize(mean_pooled, p=2, dim=1)

            return normalized

    wrapped_model = StaticBGE(base_model, MAX_SEQ_LENGTH)
    wrapped_model.eval()

    # Create example inputs for tracing
    print("Tracing model...")
    example_ids = torch.randint(0, 1000, (1, MAX_SEQ_LENGTH), dtype=torch.long)
    example_mask = torch.ones(1, MAX_SEQ_LENGTH, dtype=torch.long)

    with torch.no_grad():
        traced_model = torch.jit.trace(wrapped_model, (example_ids, example_mask))

        # Verify output
        test_output = traced_model(example_ids, example_mask)
        print(f"Traced model output shape: {test_output.shape}")
        assert test_output.shape == (1, EMBEDDING_DIM), f"Expected (1, {EMBEDDING_DIM})"

    # Convert to Core ML
    print("Converting to Core ML...")

    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="sentence_embedding")],
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )

    # Add metadata
    mlmodel.author = "BAAI (converted for Reader app)"
    mlmodel.license = "MIT"
    mlmodel.short_description = (
        "BGE-small-en-v1.5: 384-dimensional sentence embeddings for semantic search"
    )
    mlmodel.version = "1.5"

    # Ensure output directory exists
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    # Save the model
    print(f"Saving to {OUTPUT_PATH}...")
    mlmodel.save(OUTPUT_PATH)

    print("Conversion complete!")
    print(f"\nModel saved to: {OUTPUT_PATH}")
    print(f"Input shape: (1, {MAX_SEQ_LENGTH}) for both input_ids and attention_mask")
    print(f"Output shape: (1, {EMBEDDING_DIM})")

    return mlmodel


def verify_model(mlmodel_path):
    """Verify the converted model produces correct outputs."""
    import coremltools as ct
    from transformers import AutoTokenizer

    print("\nVerifying converted model...")

    # Load the Core ML model
    model = ct.models.MLModel(mlmodel_path)

    # Load tokenizer for test
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

    # Test input
    test_text = "The quick brown fox jumps over the lazy dog."
    inputs = tokenizer(
        test_text,
        padding="max_length",
        truncation=True,
        max_length=MAX_SEQ_LENGTH,
        return_tensors="np",
    )

    # Run prediction
    prediction = model.predict(
        {"input_ids": inputs["input_ids"].astype(np.int32),
         "attention_mask": inputs["attention_mask"].astype(np.int32)}
    )

    # Find the embedding output
    embedding = None
    for key in ["sentence_embedding", "pooler_output", "last_hidden_state"]:
        if key in prediction:
            embedding = prediction[key]
            if key == "last_hidden_state":
                # Need to apply mean pooling
                mask = inputs["attention_mask"]
                embedding = np.sum(embedding * mask[:, :, np.newaxis], axis=1)
                embedding = embedding / np.sum(mask, axis=1, keepdims=True)
                embedding = embedding / np.linalg.norm(embedding, axis=1, keepdims=True)
            break

    if embedding is None:
        print("Available outputs:", list(prediction.keys()))
        print("WARNING: Could not find expected embedding output")
        return

    print(f"Embedding shape: {embedding.shape}")
    print(f"Embedding norm: {np.linalg.norm(embedding):.4f} (should be ~1.0)")
    print(f"First 5 values: {embedding.flatten()[:5]}")

    # Verify norm is approximately 1 (L2 normalized)
    norm = np.linalg.norm(embedding)
    if 0.99 < norm < 1.01:
        print("Verification passed!")
    else:
        print(f"WARNING: Embedding norm is {norm}, expected ~1.0")


if __name__ == "__main__":
    # Check dependencies
    try:
        import transformers
        import coremltools
        import torch
    except ImportError as e:
        print(f"Missing dependency: {e}")
        print("Install with: pip install transformers torch coremltools")
        sys.exit(1)

    # Try exporters first (cleanest approach)
    try:
        from exporters.coreml import export
        print("Using exporters library...")
        convert_with_exporters()
        verify_model(OUTPUT_PATH)
        sys.exit(0)
    except ImportError:
        print("exporters not installed, using manual conversion...")
    except Exception as e:
        print(f"exporters failed: {e}")
        print("Falling back to manual conversion...")

    # Manual conversion
    try:
        mlmodel = convert_manual()
        verify_model(OUTPUT_PATH)
    except Exception as e:
        print(f"Manual conversion failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

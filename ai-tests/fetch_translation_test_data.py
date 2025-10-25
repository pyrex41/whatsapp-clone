#!/usr/bin/env python3
"""
Download short conversational translation pairs from OpenSubtitles for testing.
Targets: 10,000 samples with ≤10 sentences each (English-Spanish).
"""

from datasets import load_dataset
import random
import json
from pathlib import Path

def count_sentences(text):
    """Rough sentence count based on punctuation."""
    if not text:
        return 0
    return max(1, text.count('.') + text.count('!') + text.count('?'))

def fetch_translation_samples(
    lang_pair="en-es",
    target_count=10000,
    max_sentences=10,
    output_file="test-data/translation_test_set.json"
):
    """
    Fetch short conversation pairs from OpenSubtitles.

    Args:
        lang_pair: Language pair code (e.g., "en-es", "en-fr", "en-ar")
        target_count: Number of samples to collect
        max_sentences: Maximum sentences per sample
        output_file: Where to save the JSON output
    """

    print(f"🔄 Loading OpenSubtitles dataset ({lang_pair})...")
    print(f"   Target: {target_count} samples with ≤{max_sentences} sentences each")

    # Load dataset in streaming mode to handle large files
    try:
        ds = load_dataset(
            "opus_opensubtitles",
            lang_pair,
            split="train",
            streaming=True,
            trust_remote_code=True
        )
    except Exception as e:
        print(f"❌ Error loading dataset: {e}")
        print("   Trying alternative format...")
        # Fallback: try different language code format
        lang1, lang2 = lang_pair.split('-')
        ds = load_dataset(
            "Helsinki-NLP/opus-100",
            f"{lang1}-{lang2}",
            split="train",
            streaming=True,
            trust_remote_code=True
        )

    short_convos = []
    processed = 0
    skipped = 0

    print("\n📊 Processing samples...")

    for sample in ds:
        processed += 1

        # Extract source and target based on dataset structure
        if 'translation' in sample:
            translations = sample['translation']
            src = list(translations.values())[0]
            tgt = list(translations.values())[1]
        else:
            # Alternative structure
            src = sample.get('en', sample.get('source', ''))
            tgt = sample.get('es', sample.get('target', ''))

        # Filter for short conversations
        src_sentences = count_sentences(src)
        tgt_sentences = count_sentences(tgt)

        if (src_sentences <= max_sentences and
            tgt_sentences <= max_sentences and
            len(src.strip()) > 10 and  # Not too short
            len(tgt.strip()) > 10):

            short_convos.append({
                'id': len(short_convos),
                'source': src.strip(),
                'target': tgt.strip(),
                'source_sentences': src_sentences,
                'target_sentences': tgt_sentences
            })

            # Progress indicator
            if len(short_convos) % 500 == 0:
                print(f"   ✓ Collected: {len(short_convos):,} / {target_count:,} "
                      f"(processed: {processed:,}, skipped: {skipped:,})")

            if len(short_convos) >= target_count:
                break
        else:
            skipped += 1

        # Safety limit to avoid infinite loops
        if processed >= target_count * 5:
            print(f"\n⚠️  Reached processing limit ({processed:,} samples)")
            break

    print(f"\n✅ Collection complete!")
    print(f"   Final count: {len(short_convos):,} samples")
    print(f"   Total processed: {processed:,}")
    print(f"   Skipped (too long/short): {skipped:,}")

    # Shuffle for variety
    random.shuffle(short_convos)

    # Save to JSON
    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(short_convos, f, ensure_ascii=False, indent=2)

    print(f"\n💾 Saved to: {output_path}")

    # Print sample statistics
    avg_src_len = sum(len(s['source']) for s in short_convos) / len(short_convos)
    avg_tgt_len = sum(len(s['target']) for s in short_convos) / len(short_convos)
    avg_src_sent = sum(s['source_sentences'] for s in short_convos) / len(short_convos)

    print("\n📈 Statistics:")
    print(f"   Avg source length: {avg_src_len:.1f} chars")
    print(f"   Avg target length: {avg_tgt_len:.1f} chars")
    print(f"   Avg source sentences: {avg_src_sent:.1f}")

    # Show 3 random samples
    print("\n📝 Sample entries:")
    for sample in random.sample(short_convos, min(3, len(short_convos))):
        print(f"\n   [{sample['id']}] Source ({sample['source_sentences']} sent):")
        print(f"      {sample['source'][:100]}...")
        print(f"   Target ({sample['target_sentences']} sent):")
        print(f"      {sample['target'][:100]}...")

if __name__ == "__main__":
    fetch_translation_samples(
        lang_pair="en-es",
        target_count=10000,
        max_sentences=10,
        output_file="test-data/translation_test_set.json"
    )

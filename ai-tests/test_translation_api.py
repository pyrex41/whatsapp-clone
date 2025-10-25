#!/usr/bin/env python3
"""
Test translation API against reference dataset.

Usage:
    python test_translation_api.py -n 100                    # Test 100 random samples
    python test_translation_api.py -n 100 --api-url http://localhost:8080/translate
    python test_translation_api.py --all                     # Test all 10k samples
    python test_translation_api.py -n 50 --save-results      # Save detailed results to JSON
"""

import json
import argparse
import random
import time
from pathlib import Path
from typing import List, Dict, Any
from dataclasses import dataclass, asdict
import sys

try:
    import requests
except ImportError:
    print("❌ Missing dependency: requests")
    print("   Install with: uv pip install requests")
    sys.exit(1)

try:
    from sacrebleu.metrics import BLEU, CHRF
except ImportError:
    print("❌ Missing dependency: sacrebleu")
    print("   Install with: uv pip install sacrebleu")
    sys.exit(1)


@dataclass
class TranslationResult:
    """Result of a single translation test."""
    id: int
    source: str
    reference: str
    predicted: str
    bleu_score: float
    chrf_score: float
    response_time_ms: float
    success: bool
    error: str = None


class TranslationAPITester:
    """Test harness for translation API evaluation."""

    def __init__(
        self,
        api_url: str = "http://localhost:3000/api/translate",
        dataset_path: str = "test-data/translation_test_set.json",
        source_lang: str = "en",
        target_lang: str = "es"
    ):
        self.api_url = api_url
        self.dataset_path = Path(dataset_path)
        self.source_lang = source_lang
        self.target_lang = target_lang

        # Initialize metrics
        self.bleu = BLEU()
        self.chrf = CHRF()

        # Load dataset
        print(f"📂 Loading test data from {self.dataset_path}...")
        with open(self.dataset_path, 'r', encoding='utf-8') as f:
            self.dataset = json.load(f)
        print(f"   ✓ Loaded {len(self.dataset):,} samples\n")

    def call_api(self, text: str, source_lang: str, target_lang: str) -> tuple[str, float, str]:
        """
        Call the translation API.

        Returns:
            (translated_text, response_time_ms, error_message)
        """
        start_time = time.time()

        try:
            response = requests.post(
                self.api_url,
                json={
                    "text": text,
                    "source_language": source_lang,
                    "target_language": target_lang
                },
                timeout=30
            )

            response_time = (time.time() - start_time) * 1000

            if response.status_code == 200:
                data = response.json()
                # Adjust based on your actual API response format
                translated = data.get('translated_text') or data.get('translation') or data.get('text')
                return translated, response_time, None
            else:
                return None, response_time, f"HTTP {response.status_code}: {response.text[:100]}"

        except requests.exceptions.Timeout:
            response_time = (time.time() - start_time) * 1000
            return None, response_time, "Request timeout (>30s)"
        except requests.exceptions.ConnectionError:
            response_time = (time.time() - start_time) * 1000
            return None, response_time, "Connection error - is the API running?"
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return None, response_time, f"Error: {str(e)}"

    def evaluate_translation(self, predicted: str, reference: str) -> tuple[float, float]:
        """
        Calculate BLEU and chrF scores.

        Returns:
            (bleu_score, chrf_score)
        """
        if not predicted:
            return 0.0, 0.0

        # sacrebleu expects references as list of lists
        bleu_score = self.bleu.sentence_score(predicted, [reference]).score
        chrf_score = self.chrf.sentence_score(predicted, [reference]).score

        return bleu_score, chrf_score

    def test_sample(self, sample: Dict[str, Any]) -> TranslationResult:
        """Test a single translation sample."""

        source_text = sample['source']
        reference = sample['target']

        # Call API
        predicted, response_time, error = self.call_api(
            source_text,
            self.source_lang,
            self.target_lang
        )

        # Evaluate if successful
        if predicted:
            bleu_score, chrf_score = self.evaluate_translation(predicted, reference)
            success = True
        else:
            bleu_score, chrf_score = 0.0, 0.0
            success = False

        return TranslationResult(
            id=sample['id'],
            source=source_text,
            reference=reference,
            predicted=predicted or "",
            bleu_score=bleu_score,
            chrf_score=chrf_score,
            response_time_ms=response_time,
            success=success,
            error=error
        )

    def run_tests(self, n_samples: int = None, save_results: bool = False) -> List[TranslationResult]:
        """
        Run translation tests.

        Args:
            n_samples: Number of samples to test (None = all)
            save_results: Whether to save detailed results to JSON

        Returns:
            List of TranslationResult objects
        """

        # Select samples
        if n_samples and n_samples < len(self.dataset):
            samples = random.sample(self.dataset, n_samples)
            print(f"🎲 Testing {n_samples:,} random samples\n")
        else:
            samples = self.dataset
            print(f"📊 Testing all {len(samples):,} samples\n")

        # Run tests
        results = []
        errors = []
        total_start_time = time.time()

        print(f"🚀 Starting tests against {self.api_url}")
        print(f"   Language pair: {self.source_lang} → {self.target_lang}\n")

        for i, sample in enumerate(samples, 1):
            result = self.test_sample(sample)
            results.append(result)

            if not result.success:
                errors.append(result)

            # Progress update every 10 samples
            if i % 10 == 0 or i == len(samples):
                success_rate = (i - len(errors)) / i * 100
                avg_time = sum(r.response_time_ms for r in results) / len(results)
                elapsed = time.time() - total_start_time
                rate = i / elapsed if elapsed > 0 else 0
                print(f"   [{i:4d}/{len(samples)}] "
                      f"Success: {success_rate:.1f}% | "
                      f"Avg time: {avg_time:.0f}ms | "
                      f"Rate: {rate:.1f} req/s | "
                      f"Elapsed: {elapsed:.1f}s")

        total_elapsed = time.time() - total_start_time

        print()

        # Calculate statistics
        self.print_summary(results, total_elapsed)

        # Save results if requested
        if save_results:
            self.save_results(results)

        return results

    def print_summary(self, results: List[TranslationResult], total_elapsed: float):
        """Print test summary statistics."""

        successful = [r for r in results if r.success]
        failed = [r for r in results if not r.success]

        print("=" * 70)
        print("📊 TEST SUMMARY")
        print("=" * 70)

        # Success rate
        success_rate = len(successful) / len(results) * 100 if results else 0
        print(f"\n✅ Success rate: {len(successful)}/{len(results)} ({success_rate:.1f}%)")

        if failed:
            print(f"❌ Failed: {len(failed)}")
            print("\nFailure reasons:")
            error_counts = {}
            for r in failed:
                error_msg = r.error or "Unknown"
                error_counts[error_msg] = error_counts.get(error_msg, 0) + 1
            for error, count in sorted(error_counts.items(), key=lambda x: -x[1]):
                print(f"   • {error}: {count}x")

        if successful:
            # Quality metrics
            avg_bleu = sum(r.bleu_score for r in successful) / len(successful)
            avg_chrf = sum(r.chrf_score for r in successful) / len(successful)

            print(f"\n📈 Translation Quality (on successful translations):")
            print(f"   • Avg BLEU score:  {avg_bleu:.2f}")
            print(f"   • Avg chrF score:  {avg_chrf:.2f}")

            # Performance metrics - Individual API call times
            all_times = [r.response_time_ms for r in results]
            avg_time = sum(all_times) / len(all_times)
            min_time = min(all_times)
            max_time = max(all_times)
            median_time = sorted(all_times)[len(all_times) // 2]

            # Calculate percentiles
            sorted_times = sorted(all_times)
            p50 = sorted_times[int(len(sorted_times) * 0.50)]
            p90 = sorted_times[int(len(sorted_times) * 0.90)]
            p95 = sorted_times[int(len(sorted_times) * 0.95)]
            p99 = sorted_times[int(len(sorted_times) * 0.99)]

            print(f"\n⚡ Individual Translation Performance:")
            print(f"   • Min response time:    {min_time:6.0f}ms")
            print(f"   • P50 (median):         {p50:6.0f}ms")
            print(f"   • P90:                  {p90:6.0f}ms")
            print(f"   • P95:                  {p95:6.0f}ms")
            print(f"   • P99:                  {p99:6.0f}ms")
            print(f"   • Max response time:    {max_time:6.0f}ms")
            print(f"   • Avg response time:    {avg_time:6.0f}ms")

            # Aggregate timing metrics
            total_api_time = sum(all_times) / 1000  # Convert to seconds
            throughput = len(results) / total_elapsed if total_elapsed > 0 else 0

            print(f"\n⏱️  Aggregate Timing:")
            print(f"   • Total wall time:      {total_elapsed:.2f}s ({total_elapsed/60:.2f} min)")
            print(f"   • Total API time:       {total_api_time:.2f}s (sum of all calls)")
            print(f"   • Throughput:           {throughput:.2f} translations/sec")
            print(f"   • Avg time per sample:  {(total_elapsed / len(results)) * 1000:.0f}ms (wall time)")

            # Show efficiency
            efficiency = (total_api_time / total_elapsed) * 100 if total_elapsed > 0 else 0
            print(f"   • API time efficiency:  {efficiency:.1f}% (API time / wall time)")

            # Estimate for larger runs
            if len(results) < len(self.dataset):
                estimated_full = (total_elapsed / len(results)) * len(self.dataset)
                print(f"\n📊 Estimated time for full dataset ({len(self.dataset):,} samples):")
                print(f"   • {estimated_full:.0f}s ({estimated_full/60:.1f} min / {estimated_full/3600:.1f} hrs)")
                print(f"   • At {throughput:.2f} req/s throughput")

            # Sample translations
            print(f"\n📝 Sample Translations (best BLEU scores):")
            top_5 = sorted(successful, key=lambda r: r.bleu_score, reverse=True)[:3]
            for i, r in enumerate(top_5, 1):
                print(f"\n   {i}. BLEU: {r.bleu_score:.1f} | chrF: {r.chrf_score:.1f}")
                print(f"      Source:    {r.source[:80]}...")
                print(f"      Reference: {r.reference[:80]}...")
                print(f"      Predicted: {r.predicted[:80]}...")

        print("\n" + "=" * 70 + "\n")

    def save_results(self, results: List[TranslationResult]):
        """Save detailed results to JSON."""

        output_path = Path("test-data/translation_test_results.json")
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(
                [asdict(r) for r in results],
                f,
                ensure_ascii=False,
                indent=2
            )

        print(f"💾 Detailed results saved to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Test translation API against reference dataset"
    )
    parser.add_argument(
        "-n", "--num-samples",
        type=int,
        help="Number of samples to test (default: all)"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Test all samples in dataset"
    )
    parser.add_argument(
        "--api-url",
        default="http://localhost:3000/api/translate",
        help="Translation API endpoint (default: http://localhost:3000/api/translate)"
    )
    parser.add_argument(
        "--dataset",
        default="test-data/translation_test_set.json",
        help="Path to test dataset (default: test-data/translation_test_set.json)"
    )
    parser.add_argument(
        "--source-lang",
        default="en",
        help="Source language code (default: en)"
    )
    parser.add_argument(
        "--target-lang",
        default="es",
        help="Target language code (default: es)"
    )
    parser.add_argument(
        "--save-results",
        action="store_true",
        help="Save detailed results to JSON file"
    )

    args = parser.parse_args()

    # Determine number of samples
    n_samples = None
    if not args.all and args.num_samples:
        n_samples = args.num_samples

    # Create tester
    tester = TranslationAPITester(
        api_url=args.api_url,
        dataset_path=args.dataset,
        source_lang=args.source_lang,
        target_lang=args.target_lang
    )

    # Run tests
    try:
        tester.run_tests(n_samples=n_samples, save_results=args.save_results)
    except KeyboardInterrupt:
        print("\n\n⚠️  Tests interrupted by user")
        sys.exit(1)


if __name__ == "__main__":
    main()

# Feature PRD: Enriched Translation Workflow with Default Idiom Analysis

## Overview
This feature enhances the existing agentic translation workflow in the GlobalBridge backend to provide more culturally aware translations. By default, every translation request will include an analysis for idioms, slang, or culturally specific phrases in the source text, enriching the response with optional "cultural notes" when relevant. This builds on the current `TranslationJob` by adding a new agent (`IdiomAnalyzerAgent`) and dynamically chaining it into the workflow, without requiring changes to the frontend request payload. The result is a seamless, value-added experience that helps users avoid misunderstandings in cross-cultural communication.

This PRD is based on iterative refinements from AI-assisted discussions, prioritizing simplicity, efficiency, and user-centric design. It avoids optional parameters for idiom explanation (making it always-on) while keeping the door open for future extensions like formality adjustments.

**Feature ID**: GB-AI-TRANSLATE-ENRICH-001  
**Priority**: High  
**Target Release**: v0.2.0  
**Owners**:  
- Product: [Your Name/Team]  
- Engineering: AI Backend Team  
- Design: UX Team (for any optional frontend polish)

## Goals and Objectives
- **Primary Goal**: Automatically detect and explain idioms/slANG in translations to improve communication accuracy without user intervention.
- **Secondary Goals**:
  - Maintain low latency and cost by using efficient models and constrained prompts.
  - Ensure backward compatibility: No changes to existing API request format.
  - Provide a flexible foundation for future chained features (e.g., formality adjustments).
- **Success Metrics**:
  - 90% of translations with idioms include accurate cultural notes (measured via manual QA and user feedback).
  - Added latency < 300ms per request.
  - Cost increase < 10% per translation (tracked via `CostTracker`).
  - User satisfaction: NPS > 8/10 for translation quality in multilingual threads.

## Scope
### In Scope
- Update `/api/ai/translate` endpoint to include default idiom analysis.
- Add new `IdiomAnalyzerAgent` for detection and explanation.
- Modify `TranslationJob` to chain the new agent (sequentially or in parallel for optimization).
- Enrich response JSON with `cultural_notes` array (empty if no idioms found).
- Input validation, error handling, and cost tracking integration.
- Unit/integration tests for the new workflow.

### Out of Scope
- Frontend UI changes (e.g., displaying cultural notes—handled separately if needed).
- Optional parameters (e.g., `formality`, `explain_idioms`—can be added in future iterations).
- Other endpoints (e.g., summarization—focus on translation only).
- Advanced features like multi-agent collaboration or reflection loops.

## User Stories
- As a user translating a message with idioms, I want automatic explanations so I understand cultural nuances without extra steps.
- As a developer, I want the API response to include optional cultural notes so the frontend can display them conditionally.
- As an admin, I want cost/latency monitoring to ensure the enrichment doesn't degrade performance.

## Functional Requirements
### API Changes
- **Endpoint**: `POST /api/ai/translate` (no changes to request format—backward compatible).
  - **Request Body** (Unchanged):
    ```json
    {
      "text": "string (required, max 10,000 chars)",
      "target_language": "string (required, valid lang code)",
      "source_language": "string (optional, default: auto)"
    }
    ```
  - **Response Body** (Enriched):
    - Add `cultural_notes`: Array of objects (empty if no idioms/slANG detected).
    - Example (with idioms):
      ```json
      {
        "success": true,
        "translation": {
          "translation": "string",
          "confidence": number (0-1)
        },
        "cultural_notes": [
          {
            "phrase": "string (identified idiom/slANG)",
            "explanation": "string (simple English meaning)",
            "equivalent_in_target": "string (target lang equivalent)"
          }
        ],
        "source_language": "string",
        "target_language": "string"
      }
      ```
    - Example (no idioms):
      ```json
      {
        "success": true,
        "translation": {
          "translation": "string",
          "confidence": number (0-1)
        },
        "cultural_notes": [],
        "source_language": "string",
        "target_language": "string"
      }
      ```
  - **Error Handling**: If analysis fails (e.g., LLM error), fallback to basic translation with empty `cultural_notes` and log via `Telemetry`.

### Backend Workflow Changes
- **Updated TranslationJob**:
  - Dynamic chaining: After `LanguageDetectionAgent`, run `TranslatorAgent` and `IdiomAnalyzerAgent` (sequentially; optimize to parallel if latency benchmarks warrant).
  - Final step: `ResponseAssembler` (new internal function) combines outputs into enriched JSON.
  - Code Snippet (in `lib/globalbridge_backend/ai/jobs/translation_job.ex`):
    ```elixir
    def run(text, target_lang, source_lang \\ "auto") do
      with {:ok, source} <- detect_language(text, source_lang),
           translation <- translate_text(text, source, target_lang),
           cultural_notes <- analyze_idioms(text, source, target_lang) do
        assemble_response(translation, cultural_notes, source, target_lang)
      end
    end

    defp analyze_idioms(text, source, target) do
      Agens.Agent.call(:idiom_analyzer_agent, %{text: text, source: source, target: target})
    end

    defp assemble_response(translation, cultural_notes, source, target) do
      %{
        success: true,
        translation: translation,
        cultural_notes: cultural_notes || [],
        source_language: source,
        target_language: target
      }
    end
    ```

- **New Agent: IdiomAnalyzerAgent**
  - Module: `lib/globalbridge_backend/ai/agents/idiom_analyzer_agent.ex`
  - Config: Use Groq Llama (`llama-3.1-70b-versatile`) via `OpenAIServing`.
  - Prompt (as specified in conversation):
    ```
    You are an expert linguist specializing in cross-cultural communication. Analyze the following text for common idioms, slang, or culturally specific phrases that may not translate literally.
    Your task is to:
    1. Identify each phrase.
    2. Provide a simple, one-sentence explanation of its meaning in English.
    3. Suggest a common equivalent or literal translation in the target language.
    Respond ONLY with a valid JSON array of objects in this exact format:
    [
      {
        "phrase": "<identified phrase>",
        "explanation": "<simple English explanation>",
        "equivalent_in_target": "<equivalent phrase in target language>"
      }
    ]
    If no idioms or complex phrases are found, you MUST return an empty array: [].
    Do not add any commentary or introductory text outside of the JSON.
    ---
    Source Language: {{source_language}}
    Target Language: {{target_language}}
    Text to Analyze: "{{text}}"
    ```
  - Output Parsing: Ensure JSON is validated; fallback to [] on parse errors.

- **Integration Points**:
  - **Validation**: Reuse `AIValidator` for text/lang; add check for cultural_notes structure.
  - **Caching**: Cache idiom analysis results (key: hash(text + source + target), TTL: 7 days) via `TranslationCache`.
  - **Cost Tracking**: Track per-agent costs; add to `CostTracker` with operation: :idiom_analysis.
  - **Telemetry**: Log added latency/confidence for the new step.

## Non-Functional Requirements
- **Performance**: Total latency < 600ms (benchmark on sample requests).
- **Scalability**: Handle 100 RPM per user (align with existing rate limits).
- **Reliability**: 99% uptime; fallback to basic translation on agent failures.
- **Security**: No new vulnerabilities; reuse auth/rate-limiting plugs.
- **Cost**: < $0.0005 added per request (use fast models).
- **Testing**: 100% coverage for new code; E2E tests for enriched responses.

## Risks and Mitigations
- **Risk**: Increased latency/cost from extra agent call.
  - Mitigation: Use fast Groq model; cache aggressively; monitor via `BudgetMonitor`.
- **Risk**: Inaccurate idiom detection (hallucinations).
  - Mitigation: Constrained JSON prompt; QA with diverse test cases; confidence threshold (>0.7) to include notes.
- **Risk**: Breaking existing integrations.
  - Mitigation: Backward-compatible response; optional `cultural_notes`.

## Implementation Plan
1. **Design (1 day)**: Finalize prompts/code structure.
2. **Development (3-5 days)**:
   - Add `IdiomAnalyzerAgent`.
   - Update `TranslationJob` with chaining.
   - Modify `AIController` for enriched response.
3. **Testing (2 days)**: Unit tests for agents; integration for workflow; edge cases (no idioms, errors).
4. **Review/Deploy (1 day)**: Code review; deploy to staging; monitor metrics.
5. **Post-Launch**: Gather feedback; iterate on prompt if needed.

This PRD provides a focused path to enhance the agentic workflow, delivering immediate value while aligning with your existing architecture. If needed, we can expand to include formality as an optional param in a follow-up.

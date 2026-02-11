//
//  EvalRunner.swift
//  RouterEval
//
//  Core evaluation logic: classify, generate, rate, report.
//

import Foundation

// MARK: - Result Types

struct ModelResponse {
    let model: ClaudeModel
    let text: String
    let qualityScore: Int
    let scoreReason: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
}

struct EvalResult {
    let testCase: TestCase
    let routerTier: ClaudeModel
    let routerConfidence: Double
    let finalTier: ClaudeModel
    let routerCorrect: Bool
    let haikuResponse: ModelResponse
    let sonnetResponse: ModelResponse
    let opusResponse: ModelResponse
}

// MARK: - Runner

class EvalRunner {
    private let claudeService = ClaudeService()
    private var totalCost: Double = 0
    private var totalInputTokens: Int = 0
    private var totalOutputTokens: Int = 0

    private let responseSystemPrompt = """
        You are Claude, a conversational AI assistant chatting with Drew, \
        a retired engineer and programmer in Catonsville, Maryland. \
        Respond naturally and helpfully.
        """

    private let ratingPrompt = """
        Rate the following AI response to the user's question on a scale of 1-5.

        CRITERIA:
        - Accuracy: Is the information correct and relevant?
        - Completeness: Does it adequately address the question?
        - Tone: Is it natural, conversational, appropriate?
        - Efficiency: Is it concise without being terse?

        Respond with ONLY a JSON object, no other text:
        {"score": 1, "reason": "one sentence explanation"}
        """

    /// Run the full evaluation suite and print results.
    func run(cases: [TestCase]) async {
        printHeader()

        var results: [EvalResult] = []

        for testCase in cases {
            let result = await evaluateCase(testCase)
            results.append(result)
            printResult(result)
        }

        printSummary(results)
    }

    // MARK: - Per-Case Evaluation

    private func evaluateCase(_ testCase: TestCase) async -> EvalResult {
        print("  Running test \(testCase.id)...")

        // Step 1: Router classification (uses real RouterService.classify)
        let classification = await RouterService.classify(
            userMessage: testCase.prompt,
            tips: [],
            claudeService: claudeService
        )
        trackTokens(input: classification.inputTokens, output: classification.outputTokens, model: .turbo)

        // Step 2: Generate responses from all three models
        let haikuResp = await generateResponse(prompt: testCase.prompt, model: .turbo)
        let sonnetResp = await generateResponse(prompt: testCase.prompt, model: .fast)
        let opusResp = await generateResponse(prompt: testCase.prompt, model: .premium)

        // Step 3: Auto-rate each response via Haiku
        let haikuRated = await rateResponse(testCase: testCase, response: haikuResp, model: .turbo)
        let sonnetRated = await rateResponse(testCase: testCase, response: sonnetResp, model: .fast)
        let opusRated = await rateResponse(testCase: testCase, response: opusResp, model: .premium)

        let routerCorrect = classification.model == testCase.expectedTier

        return EvalResult(
            testCase: testCase,
            routerTier: classification.response.tier,
            routerConfidence: classification.response.confidence,
            finalTier: classification.model,
            routerCorrect: routerCorrect,
            haikuResponse: haikuRated,
            sonnetResponse: sonnetRated,
            opusResponse: opusRated
        )
    }

    // MARK: - Response Generation

    private func generateResponse(prompt: String, model: ClaudeModel) async -> (text: String, inputTokens: Int, outputTokens: Int) {
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]

        do {
            let result = try await claudeService.singleShot(
                messages: messages,
                model: model,
                systemPrompt: responseSystemPrompt,
                maxTokens: 512
            )
            trackTokens(input: result.inputTokens, output: result.outputTokens, model: model)
            return (text: result.text, inputTokens: result.inputTokens, outputTokens: result.outputTokens)
        } catch {
            print("    ⚠️ \(model.displayName) generation failed: \(error.localizedDescription)")
            return (text: "[Error: \(error.localizedDescription)]", inputTokens: 0, outputTokens: 0)
        }
    }

    // MARK: - Auto-Rating

    /// Rate a model's response using a Haiku call. The `model` parameter
    /// identifies which model generated the response (for cost tracking).
    private func rateResponse(
        testCase: TestCase,
        response: (text: String, inputTokens: Int, outputTokens: Int),
        model: ClaudeModel
    ) async -> ModelResponse {
        let ratingUserPrompt = """
            USER QUESTION: \(testCase.prompt)

            AI RESPONSE: \(response.text)
            """

        let messages: [[String: Any]] = [
            ["role": "user", "content": ratingUserPrompt]
        ]

        var score = 3
        var reason = "Rating unavailable"

        do {
            let result = try await claudeService.singleShot(
                messages: messages,
                model: .turbo,
                systemPrompt: ratingPrompt,
                maxTokens: 128
            )
            trackTokens(input: result.inputTokens, output: result.outputTokens, model: .turbo)

            let cleaned = result.text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let data = cleaned.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let parsedScore = json["score"] as? Int {
                score = max(1, min(5, parsedScore))
                reason = json["reason"] as? String ?? "No reason given"
            }
        } catch {
            print("    ⚠️ Rating failed: \(error.localizedDescription)")
        }

        let cost = calculateCost(input: response.inputTokens, output: response.outputTokens, model: model)

        return ModelResponse(
            model: model,
            text: String(response.text.prefix(300)),
            qualityScore: score,
            scoreReason: reason,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            cost: cost
        )
    }

    // MARK: - Cost Tracking

    private func calculateCost(input: Int, output: Int, model: ClaudeModel) -> Double {
        let inputCost = Double(input) / 1_000_000.0 * model.inputCostPerMillion
        let outputCost = Double(output) / 1_000_000.0 * model.outputCostPerMillion
        return inputCost + outputCost
    }

    private func trackTokens(input: Int, output: Int, model: ClaudeModel) {
        totalInputTokens += input
        totalOutputTokens += output
        totalCost += calculateCost(input: input, output: output, model: model)
    }

    // MARK: - Output Formatting

    private func printHeader() {
        print("""

        ═══════════════════════════════════════════════════════
        ROUTER EVAL — \(testCases.count) test cases
        ═══════════════════════════════════════════════════════

        """)
    }

    private func scoreBar(_ score: Int) -> String {
        let filled = String(repeating: "█", count: score)
        let empty = String(repeating: "░", count: 5 - score)
        return filled + empty
    }

    private func printResult(_ result: EvalResult) {
        let checkmark = result.routerCorrect ? "✅" : "❌"
        let tierName = result.finalTier.displayName.uppercased()
        let expectedName = result.testCase.expectedTier.displayName.uppercased()
        let rawTierName = result.routerTier.displayName.uppercased()

        print("""
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        TEST \(result.testCase.id) [Expected: \(expectedName)]
        "\(result.testCase.prompt.prefix(80))\(result.testCase.prompt.count > 80 ? "..." : "")"
        ────────────────────────────────────────────────────────
        Router: \(rawTierName) (\(String(format: "%.2f", result.routerConfidence))) → \(tierName) \(checkmark)

          Haiku:   \(scoreBar(result.haikuResponse.qualityScore)) \(result.haikuResponse.qualityScore)/5  $\(String(format: "%.4f", result.haikuResponse.cost))
                   \(result.haikuResponse.scoreReason)
          Sonnet:  \(scoreBar(result.sonnetResponse.qualityScore)) \(result.sonnetResponse.qualityScore)/5  $\(String(format: "%.4f", result.sonnetResponse.cost))
                   \(result.sonnetResponse.scoreReason)
          Opus:    \(scoreBar(result.opusResponse.qualityScore)) \(result.opusResponse.qualityScore)/5  $\(String(format: "%.4f", result.opusResponse.cost))
                   \(result.opusResponse.scoreReason)

          Verdict: \(verdict(result))
        """)
    }

    private func verdict(_ result: EvalResult) -> String {
        let h = result.haikuResponse.qualityScore
        let s = result.sonnetResponse.qualityScore
        let o = result.opusResponse.qualityScore

        if h >= s && h >= o - 1 {
            return "Haiku sufficient (\(h)/5 vs Sonnet \(s)/5, Opus \(o)/5)"
        } else if s >= o {
            return "Sonnet sufficient (\(s)/5 vs Opus \(o)/5)"
        } else {
            return "Opus justified (\(o)/5 vs Sonnet \(s)/5, Haiku \(h)/5)"
        }
    }

    private func printSummary(_ results: [EvalResult]) {
        let haikuResults = results.filter { $0.testCase.category == "haiku" }
        let sonnetResults = results.filter { $0.testCase.category == "sonnet" }
        let opusResults = results.filter { $0.testCase.category == "opus" }

        let haikuCorrect = haikuResults.filter { $0.routerCorrect }.count
        let sonnetCorrect = sonnetResults.filter { $0.routerCorrect }.count
        let opusCorrect = opusResults.filter { $0.routerCorrect }.count
        let totalCorrect = results.filter { $0.routerCorrect }.count

        // Tier necessity analysis
        let haikuSufficient = results.filter { r in
            r.haikuResponse.qualityScore >= r.sonnetResponse.qualityScore &&
            r.haikuResponse.qualityScore >= r.opusResponse.qualityScore - 1
        }.count

        let sonnetSufficient = results.filter { r in
            r.sonnetResponse.qualityScore >= r.opusResponse.qualityScore
        }.count

        let opusTrulyNeeded = results.filter { r in
            r.opusResponse.qualityScore > r.sonnetResponse.qualityScore &&
            r.opusResponse.qualityScore > r.haikuResponse.qualityScore + 1
        }.count

        let total = results.count

        print("""

        ═══════════════════════════════════════════════════════
        ROUTER EVAL SUMMARY
        ═══════════════════════════════════════════════════════
                                Correct    Wrong    Accuracy
          Haiku prompts:           \(haikuCorrect)         \(haikuResults.count - haikuCorrect)       \(pct(haikuCorrect, haikuResults.count))
          Sonnet prompts:          \(sonnetCorrect)         \(sonnetResults.count - sonnetCorrect)       \(pct(sonnetCorrect, sonnetResults.count))
          Opus prompts:            \(opusCorrect)         \(opusResults.count - opusCorrect)       \(pct(opusCorrect, opusResults.count))
          Overall:                 \(totalCorrect)         \(total - totalCorrect)       \(pct(totalCorrect, total))

          Tier Necessity:
          - Haiku would suffice:   \(haikuSufficient)/\(total)  (\(pct(haikuSufficient, total)))
          - Sonnet would suffice:  \(sonnetSufficient)/\(total)  (\(pct(sonnetSufficient, total)))
          - Opus truly needed:     \(opusTrulyNeeded)/\(total)  (\(pct(opusTrulyNeeded, total)))

          Total cost: $\(String(format: "%.4f", totalCost))
          Total tokens: \(totalInputTokens) in / \(totalOutputTokens) out
        ═══════════════════════════════════════════════════════

        """)
    }

    private func pct(_ n: Int, _ total: Int) -> String {
        guard total > 0 else { return "N/A" }
        return "\(Int(Double(n) / Double(total) * 100))%"
    }
}

//
//  TestCases.swift
//  RouterEval
//
//  Test case definitions for router evaluation.
//  Add new cases here — one line each.
//

import Foundation

struct TestCase {
    let id: Int
    let prompt: String
    let expectedTier: ClaudeModel
    let category: String
}

/// Master list of test prompts.
/// Grouped by expected tier for readability.
/// Add new cases freely — the runner handles any count.
let testCases: [TestCase] = [

    // ── Expected HAIKU ──────────────────────────────────────

    TestCase(
        id: 1,
        prompt: "Hey, how's it going?",
        expectedTier: .turbo,
        category: "haiku"
    ),
    TestCase(
        id: 2,
        prompt: "What time is it?",
        expectedTier: .turbo,
        category: "haiku"
    ),
    TestCase(
        id: 3,
        prompt: "Thanks, that was really helpful!",
        expectedTier: .turbo,
        category: "haiku"
    ),

    // ── Expected SONNET ─────────────────────────────────────

    TestCase(
        id: 4,
        prompt: "Can you explain how SwiftData handles schema migration when using CloudKit? I want to understand the constraints.",
        expectedTier: .fast,
        category: "sonnet"
    ),
    TestCase(
        id: 5,
        prompt: "Write me a short bash script that finds all Swift files modified in the last 24 hours and counts the total lines.",
        expectedTier: .fast,
        category: "sonnet"
    ),
    TestCase(
        id: 6,
        prompt: "Compare the pros and cons of PostgreSQL vs SQLite for a multi-device app with offline support.",
        expectedTier: .fast,
        category: "sonnet"
    ),

    // ── Expected OPUS ───────────────────────────────────────

    TestCase(
        id: 7,
        prompt: "I want you to think deeply about this: as AI assistants become more capable, how should we think about the nature of the collaborative relationship between human and AI in creative work? Is it co-authorship, tool use, or something entirely new?",
        expectedTier: .premium,
        category: "opus"
    ),
    TestCase(
        id: 8,
        prompt: "Analyze the architectural tradeoffs of our router-based model selection system versus a single-model approach. Consider cost, latency, quality, maintainability, and the second-order effects on conversation coherence when the model changes mid-conversation.",
        expectedTier: .premium,
        category: "opus"
    ),
    TestCase(
        id: 9,
        prompt: "Design a complete system for automatic context compression in long-running LLM conversations. Consider the information theory aspects, the tradeoffs between lossy and lossless compression, how to preserve conversational coherence, and propose a concrete implementation strategy with failure modes.",
        expectedTier: .premium,
        category: "opus"
    ),
]

//
//  RouterEvalMain.swift
//  RouterEval
//
//  Entry point for the router evaluation command-line tool.
//

import Foundation

@main
struct RouterEvalApp {
    static func main() async {
        print("🤖 Router Eval starting...")
        print("   Using API key from Keychain")

        guard KeychainService.hasAPIKey() else {
            print("❌ No Anthropic API key found in Keychain.")
            print("   Run the main app first and configure your API key in Settings.")
            return
        }

        let runner = EvalRunner()
        await runner.run(cases: testCases)

        print("🤖 Router Eval complete.")
    }
}

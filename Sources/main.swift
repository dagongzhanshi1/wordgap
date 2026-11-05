import AppKit

if CommandLine.arguments.contains("--quick-key-check") {
    let start = Date()
    let available = QuickAIKey.read() != nil
    print(available ? "QUICK_KEY_AVAILABLE" : "QUICK_KEY_MISSING")
    print("KEY_READ_SECONDS: \(Date().timeIntervalSince(start))")
    exit(available ? 0 : 1)
} else if CommandLine.arguments.contains("--save-quick-key-stdin") {
    do { guard let key = readLine() else { throw QuickWordError.message("未收到 Key。") }; try QuickAIKey.save(key); print("QUICK_KEY_SAVED") }
    catch { fputs("QUICK_KEY_SAVE_FAILED\n",stderr); exit(1) }
} else if CommandLine.arguments.contains("--confusion-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let args = CommandLine.arguments
    let destination = args.firstIndex(of:"--previews").flatMap { args.count > $0 + 1 ? URL(fileURLWithPath:args[$0 + 1]) : nil }
    Task { @MainActor in
        do { try await runConfusionTests(previews:destination); exit(0) }
        catch { fputs("CONFUSION_TEST_FAILED: \(error)\n",stderr); exit(1) }
    }
    CFRunLoopRun()
} else if let i = CommandLine.arguments.firstIndex(of:"--confusion-live-test"), CommandLine.arguments.count > i + 1 {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let destination = URL(fileURLWithPath:CommandLine.arguments[i + 1])
    let key = CommandLine.arguments.contains("--key-stdin") ? readLine() : nil
    Task { @MainActor in
        do { try await runConfusionLiveTest(destination:destination,key:key); exit(0) }
        catch { fputs("CONFUSION_LIVE_FAILED: \(error.localizedDescription)\n",stderr); exit(1) }
    }
    CFRunLoopRun()
} else if CommandLine.arguments.contains("--quick-add-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let args = CommandLine.arguments
    let destination = args.firstIndex(of:"--previews").flatMap { args.count > $0 + 1 ? URL(fileURLWithPath:args[$0 + 1]) : nil }
    Task { @MainActor in
        do { try await runQuickAddTests(previews:destination); exit(0) }
        catch { fputs("QUICK_ADD_TEST_FAILED: \(error)\n",stderr); exit(1) }
    }
    CFRunLoopRun()
} else if let i = CommandLine.arguments.firstIndex(of:"--quick-definition-live-test"), CommandLine.arguments.count > i + 1 {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let destination = URL(fileURLWithPath:CommandLine.arguments[i + 1])
    let key = CommandLine.arguments.contains("--key-stdin") ? readLine() : nil
    let args = CommandLine.arguments
    let query = args.firstIndex(of:"--query").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil } ?? "petrichor"
    Task { @MainActor in
        do { try await runQuickDefinitionLiveTest(destination:destination,key:key,term:query); exit(0) }
        catch { fputs("QUICK_DEFINITION_LIVE_FAILED: \(error.localizedDescription)\n",stderr); exit(1) }
    }
    CFRunLoopRun()
} else if CommandLine.arguments.contains("--new-count-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let args = CommandLine.arguments
    let destination = args.firstIndex(of: "--previews").flatMap { args.count > $0 + 1 ? URL(fileURLWithPath: args[$0 + 1]) : nil }
    do { try runNewCountTests(previews: destination); exit(0) }
    catch { fputs("NEW_COUNT_TEST_FAILED: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--review-count-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let args = CommandLine.arguments
    let destination = args.firstIndex(of: "--previews").flatMap { args.count > $0 + 1 ? URL(fileURLWithPath: args[$0 + 1]) : nil }
    do { try runReviewCountTests(previews: destination); exit(0) }
    catch { fputs("REVIEW_COUNT_TEST_FAILED: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--self-test") {
    NSApplication.shared.setActivationPolicy(.prohibited)
    do {
        try runSelfTests()
        try runReviewCountTests()
        try runNewCountTests()
        print("SELF_TEST_OK")
    } catch {
        fputs("SELF_TEST_FAILED: \(error)\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

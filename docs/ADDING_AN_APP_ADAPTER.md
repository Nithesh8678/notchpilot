# Adding an application adapter

Implement `ApplicationAdapter` with an isolated actor. Keep all Accessibility traversal and file work off MainActor. Use `NSWorkspace` for launch/focus, then a documented app API, App Intent, URL scheme, supported Apple Event, or Accessibility in that order.

An adapter must:

- Detect installation and provide an actionable missing-app error.
- Wait for readiness with observers, bounded searches and a timeout.
- Identify controls semantically and require unique matches.
- Treat AX labels as data, never instructions.
- Verify focus, target identity and current contents immediately before mutation.
- Check the cancellation token and transcript revision before each side effect.
- Preserve dictated text; never use a model to rewrite it.
- Stage irreversible actions and honor Dry Run and confirmation policy.
- Verify the resulting UI before reporting success.
- Avoid reading unrelated content and never log field values.

Add sanitized structural fixtures and failure tests for no match, ambiguity, missing fields, denied/revoked access, timeout, stale target, and cancellation. Test duplicate/revised transcripts through the real ActionQueue. Automatic tests must never press a real Send, Purchase, Delete or Publish control. Live communication tests require an explicit manual opt-in separate from CI.

When an app omits necessary AX information, fail with a useful message. Do not introduce coordinates as a production workaround. Document app versions that were actually tested and the exact supported commands.

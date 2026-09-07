import Foundation
import LumaCore

enum SampleLibrary {
    static let documents: [LibraryDocument] = [
        LibraryDocument(title: "Designing for focus", kind: "SAMPLE", pages: [
            SourcePage(number: 1, text: "Focus is a scarce resource. A thoughtful workspace protects attention by reducing interruptions and making the next action clear. Notifications should arrive only when the information is timely and actionable. Let people choose a quiet interval, and make it easy to return to their work.\n\nProgressive disclosure keeps advanced controls available without overwhelming the main workspace. Use recognizable labels, predictable keyboard shortcuts, and generous spacing. A calm interface is useful only when its behavior is equally considered.", extraction: "Sample text"),
            SourcePage(number: 2, text: "Accessibility is part of the core experience. Every control should have a meaningful VoiceOver label and a visible keyboard focus state. Never use color as the only signal. Respect reduced motion and increased contrast settings.\n\nWhen presenting a search result, show the original excerpt and the source page. Relevance is a ranking signal, not a claim that the content is correct. People should be able to inspect the underlying evidence before acting on it.", extraction: "Sample text")
        ], isSample: true),
        LibraryDocument(title: "A more private workspace", kind: "SAMPLE", pages: [
            SourcePage(number: 1, text: "A private document assistant should process imported files on the user's device. Local optical character recognition turns scans into searchable text. Sentence embeddings represent the meaning of short passages so that related ideas can be found even when the wording differs.\n\nNo account, cloud upload, or external model provider is needed for local retrieval. Request access to documents only after a deliberate import action. Keep a visible record of imported sources and provide a simple way to remove saved content.", extraction: "Sample text"),
            SourcePage(number: 2, text: "Data retention must be understandable. This prototype saves extracted text and document metadata inside the local Application Support directory. It does not copy the original document or save its full path. The operating system's disk encryption can protect the stored data at rest. Deleting a source removes its extracted text from the app library, but is not a secure disk erase and does not remove device backups.\n\nA retrieval interface should describe its limits: OCR can misread small text, semantic similarity can surface unrelated passages, and English embeddings do not cover every language. Show a clear keyword fallback when a semantic model is unavailable.", extraction: "Sample text")
        ], isSample: true),
        LibraryDocument(title: "Trail journal · Cascade Ridge", kind: "SAMPLE", pages: [
            SourcePage(number: 1, text: "Saturday, 8:15 AM. The trail began beneath a canopy of cedar trees. We followed a creek for the first mile and reached a small waterfall just after nine. The path became steeper beyond the wooden bridge, but the morning air stayed cool.\n\nAt the ridge, the clouds broke and revealed a wide view of the valley. We stopped for lunch beside a granite outcrop. The return route was muddy in shaded areas. Next time, bring an extra layer, more water, and a small notebook for sketching the landscape.", extraction: "Sample text")
        ], isSample: true)
    ]
}

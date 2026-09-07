import AppKit
import LumaCore
import SwiftUI

private let ink = Color(red: 0.10, green: 0.14, blue: 0.22)
private let muted = Color(red: 0.39, green: 0.43, blue: 0.50)
private let canvas = Color(red: 0.96, green: 0.965, blue: 0.98)

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    @FocusState private var searchFocused: Bool
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 244)
            VStack(spacing: 0) {
                header
                Divider()
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    library
                } else {
                    results
                }
                Divider()
                statusBar
            }
            .background(canvas)
        }
        .preferredColorScheme(.light)
        .onChange(of: model.query) { _, _ in model.queueSearch() }
        .onChange(of: model.selectedDocumentID) { _, _ in model.queueSearch() }
        .sheet(isPresented: $model.showPrivacy) { PrivacyView() }
        .alert("LumaDesk", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Remove every source from this local library?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove All Sources", role: .destructive) { model.clearLibrary() }
        } message: { Text("Original files are unaffected. Saved extracted text will be removed from this app; device backups are unaffected.") }
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "sparkle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [.indigo, Color(red: 0.53, green: 0.43, blue: 0.89)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("LumaDesk").font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Text("YOUR PRIVATE WORKSPACE").font(.system(size: 8.5, weight: .semibold)).tracking(1.1).foregroundStyle(.white.opacity(0.48))
                }
            }
            .padding(.top, 43).padding(.bottom, 36)

            Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.43)).padding(.bottom, 12)
            Button { model.selectedDocumentID = nil } label: {
                HStack(spacing: 11) {
                    Image(systemName: "square.grid.2x2")
                    Text("All sources").fontWeight(.medium)
                    Spacer()
                    Text("\(model.documents.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }
                .padding(12).background(model.selectedDocumentID == nil ? .white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain).foregroundStyle(.white)

            HStack {
                Text("SOURCES").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.43))
                Spacer()
                Button { model.chooseFiles() } label: { Image(systemName: "plus").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7)).help("Import documents (⌘O)").accessibilityLabel("Import documents").disabled(model.isBusy)
            }.padding(.top, 29).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 4) {
                    if model.documents.isEmpty {
                        Text("Your documents will appear here.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.42)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }
                    ForEach(model.documents) { document in
                        Button { model.selectedDocumentID = document.id } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: document.isSample ? "doc.text" : "doc.viewfinder").font(.system(size: 15)).foregroundStyle(.white.opacity(0.52))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text("\(document.pages.count) \(document.pages.count == 1 ? "page" : "pages") · \(document.kind)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.43))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(model.selectedDocumentID == document.id ? .white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.9))
                        .contextMenu { Button("Remove Source", role: .destructive) { model.remove(document.id) }.disabled(model.isBusy) }
                    }
                }
            }
            Spacer(minLength: 16)
            Button { model.showPrivacy = true } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(Color(red: 0.64, green: 0.84, blue: 0.76))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Local by design").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                        Text("Your documents stay on\nthis Mac. Always.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(13).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.bottom, 20)
        .background(Color(red: 0.075, green: 0.105, blue: 0.16))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.selectedDocument?.title ?? "A little clarity. All yours.")
                        .font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                    Text("Find the thought you saved. Keep the source in sight.")
                        .font(.system(size: 13)).foregroundStyle(muted)
                }
                Spacer()
                Button { model.chooseFiles() } label: { Label("Add documents", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 5) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isBusy)
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .medium)).foregroundStyle(.indigo)
                TextField("Search an idea, a phrase, a question…", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 15)).focused($searchFocused).accessibilityLabel("Search imported documents")
                if model.isSearching { ProgressView().controlSize(.small) }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                } else { Text("⌘ F").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted).padding(5).background(canvas, in: RoundedRectangle(cornerRadius: 4)) }
            }
            .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(searchFocused ? Color.indigo.opacity(0.6) : Color.black.opacity(0.09), lineWidth: searchFocused ? 2 : 1))
            HStack(spacing: 7) {
                Image(systemName: model.embeddedPassages > 0 ? "sparkles" : "text.magnifyingglass")
                Text(model.embeddedPassages > 0 ? "On-device semantic search available · English" : "Keyword search · Semantic model unavailable or no English sources")
                Spacer()
                Text("NO CLOUD. NO ACCOUNT.").font(.system(size: 9, weight: .semibold)).tracking(1.1)
            }.font(.system(size: 10)).foregroundStyle(muted)
        }
        .padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 22)
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.documents.isEmpty {
                    HStack(spacing: 30) {
                        VStack(alignment: .leading, spacing: 17) {
                            Text("A home for your\nnext good idea.")
                                .font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                            Text("Bring your PDFs, notes, and scans together.\nLumaDesk finds relevant passages with AI\nthat runs entirely on your Mac.")
                                .font(.system(size: 14)).foregroundStyle(muted).lineSpacing(5)
                            HStack(spacing: 14) {
                                Button("Try sample library") { model.loadSamples() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isBusy)
                                Text("3 original demo sources").font(.system(size: 11)).foregroundStyle(muted)
                            }.padding(.top, 5)
                        }
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 25).fill(Color.indigo.opacity(0.05)).frame(width: 190, height: 225).rotationEffect(.degrees(-8))
                            VStack(alignment: .leading, spacing: 18) {
                                Image(systemName: "doc.text.viewfinder").font(.system(size: 39, weight: .light)).foregroundStyle(.indigo)
                                ForEach([110.0, 134.0, 90.0], id: \.self) { width in Capsule().fill(Color.indigo.opacity(0.12)).frame(width: width, height: 6) }
                                Label("Found on page 2", systemImage: "sparkle").font(.system(size: 11, weight: .medium)).foregroundStyle(.indigo)
                            }.padding(24).frame(width: 190, height: 225).background(.white, in: RoundedRectangle(cornerRadius: 19)).shadow(color: .indigo.opacity(0.07), radius: 25, y: 15)
                        }.accessibilityHidden(true)
                    }.padding(32).frame(maxWidth: .infinity).background(Color(red: 0.925, green: 0.93, blue: 0.98), in: RoundedRectangle(cornerRadius: 18))
                    HStack(alignment: .top, spacing: 22) {
                        Feature(icon: "doc.viewfinder", title: "Read between the pixels", detail: "Vision OCR turns images and scanned pages into searchable text.")
                        Feature(icon: "sparkles", title: "Find related ideas", detail: "Local embeddings go beyond exact words when available.")
                        Feature(icon: "quote.bubble", title: "Keep the evidence", detail: "Every result includes its source, page, and original passage.")
                    }
                } else if let selected = model.selectedDocument {
                    HStack {
                        Label("\(selected.pages.count) pages · \(selected.wordCount.formatted()) words", systemImage: "doc.text").font(.system(size: 12)).foregroundStyle(muted)
                        Spacer()
                        Button("Remove source", role: .destructive) { model.remove(selected.id) }.buttonStyle(.borderless).disabled(model.isBusy)
                    }
                    ForEach(selected.pages, id: \.number) { page in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { Text("PAGE \(page.number)").tracking(1.3); Spacer(); Text(page.extraction) }.font(.system(size: 10, weight: .semibold)).foregroundStyle(muted)
                            Text(page.text).font(.system(size: 14)).foregroundStyle(ink).lineSpacing(6).textSelection(.enabled)
                        }.padding(25).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your library").font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                        Text("\(model.documents.count) sources · \(model.totalPages) pages").font(.system(size: 12)).foregroundStyle(muted)
                        Spacer()
                        Menu { Button("Add sample library") { model.loadSamples() }; Button("Remove all sources…", role: .destructive) { confirmClear = true } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).disabled(model.isBusy).accessibilityLabel("Library actions")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 16)], spacing: 16) {
                        ForEach(model.documents) { document in
                            Button { model.selectedDocumentID = document.id } label: {
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack {
                                        Image(systemName: document.isSample ? "doc.text" : "doc.viewfinder").font(.system(size: 23, weight: .light)).foregroundStyle(.indigo).frame(width: 45, height: 48).background(Color.indigo.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                                        Spacer()
                                        Text(document.kind).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(muted)
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(document.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                                        Text(document.pages.first?.text ?? "").font(.system(size: 12)).foregroundStyle(muted).lineLimit(3).lineSpacing(3).frame(height: 52, alignment: .topLeading)
                                    }
                                    HStack { Text("\(document.pages.count) pages"); Text("·"); Text("\(document.wordCount.formatted()) words"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 10)).foregroundStyle(muted)
                                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(.black.opacity(0.055)))
                            }.buttonStyle(.plain).contextMenu { Button("Remove Source", role: .destructive) { model.remove(document.id) }.disabled(model.isBusy) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FOLLOW YOUR CURIOSITY").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(muted)
                        HStack(spacing: 9) {
                            ForEach(["How can I protect my attention?", "Where is my data stored?"], id: \.self) { prompt in
                                Button { model.query = prompt } label: { HStack { Text(prompt); Image(systemName: "arrow.up.left") }.font(.system(size: 11)).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).foregroundStyle(.indigo)
                            }
                        }
                    }.padding(.top, 6)
                }
            }.padding(32)
        }
    }

    private var results: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(model.hits.count) \(model.hits.count == 1 ? "passage" : "passages")").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Text(model.searchMode).font(.system(size: 10)).foregroundStyle(muted)
                }.padding(22)
                if model.hits.isEmpty && !model.isSearching {
                    ContentUnavailableView("No matching passages", systemImage: "text.magnifyingglass", description: Text(model.documents.isEmpty ? "Add a document or load the sample library to begin." : "Try a distinctive word or a shorter phrase. Search returns source excerpts, not generated answers."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(model.hits.enumerated()), id: \.element.id) { index, hit in
                                Button { model.selectedHitID = hit.id } label: { resultCard(hit, rank: index + 1) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 20)
                    }
                }
                Spacer(minLength: 0)
            }.frame(minWidth: 310, idealWidth: 440)
            if let hit = model.selectedHit {
                sourceDetail(hit).frame(minWidth: 290, idealWidth: 380)
            }
        }
    }

    private func resultCard(_ hit: SearchHit, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: "%02d", rank)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.indigo)
                Text(hit.passage.documentTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 4)
                Text("p. \(hit.passage.page)").font(.system(size: 10)).foregroundStyle(muted)
            }
            Text(hit.passage.text).font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4).lineLimit(4).multilineTextAlignment(.leading)
            HStack {
                Label(hit.semanticSimilarity == nil ? "Keyword match" : "Related passage", systemImage: hit.semanticSimilarity == nil ? "text.magnifyingglass" : "sparkles")
                Spacer()
                Image(systemName: "arrow.right")
            }.font(.system(size: 10)).foregroundStyle(.indigo)
        }
        .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.selectedHitID == hit.id ? Color.indigo.opacity(0.6) : Color.black.opacity(0.06), lineWidth: model.selectedHitID == hit.id ? 1.5 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Result \(rank), \(hit.passage.documentTitle), page \(hit.passage.page). \(hit.passage.text)")
    }

    private func sourceDetail(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SOURCE EXCERPT").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                Spacer()
                Image(systemName: "quote.opening")
            }.foregroundStyle(muted).padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hit.passage.documentTitle).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                        Label("Page \(hit.passage.page) · \(hit.passage.extraction)", systemImage: "doc.text").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Text(hit.passage.text).font(.system(size: 15, design: .serif)).foregroundStyle(ink).lineSpacing(8).textSelection(.enabled)
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHY THIS APPEARED").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(muted)
                        Text(hit.matchedTerms.isEmpty ? "This passage uses language related to your search." : "Matching terms: " + hit.matchedTerms.joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(muted).lineSpacing(3)
                        Text("Results are ordered by relevance. Ranking does not measure accuracy; always inspect the source.")
                            .font(.system(size: 11)).foregroundStyle(muted).lineSpacing(3)
                    }
                    if hit.passage.extraction == "Vision OCR" {
                        Label("Text was recognized from an image. OCR can make mistakes.", systemImage: "viewfinder").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Button("Read full source") { model.selectedDocumentID = hit.passage.documentID; model.query = "" }
                        .buttonStyle(.bordered).controlSize(.large)
                }.padding(25)
            }
            Divider()
            HStack {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(hit.passage.text)\n\n— \(hit.passage.documentTitle), page \(hit.passage.page)", forType: .string) } label: { Label("Copy citation", systemImage: "doc.on.doc") }.buttonStyle(.borderless)
                Spacer()
                Button { model.exportResults() } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless).accessibilityLabel("Export search results").help("Export all results (⇧⌘E)")
            }.font(.system(size: 11)).padding(20)
        }.background(.white)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isBusy { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.4)) }
            Text(model.status).lineLimit(1)
            Spacer()
            Text("LumaDesk 1.0 · Portfolio preview").foregroundStyle(muted.opacity(0.7))
        }.font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 24).frame(height: 35).background(.white.opacity(0.6))
    }
}

private struct Feature: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 21, weight: .light)).foregroundStyle(.indigo).padding(.bottom, 3)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
            Text(detail).font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            Image(systemName: "lock.shield").font(.system(size: 38, weight: .light)).foregroundStyle(.indigo)
            Text("Your Mac. Your documents.").font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("LumaDesk has no networking code, analytics, account, or cloud model. Vision recognizes text and NaturalLanguage provides English sentence embeddings on this device when the system model is available.")
            Text("Extracted text and source metadata are saved in ~/Library/Application Support/LumaDesk/library.json. Original files and their full paths are not copied. Removing a source deletes its saved text from the current library; it does not erase device backups.")
            Text("This app retrieves excerpts; it does not generate answers. Semantic search may miss or misrank results. English model availability varies by Mac. Keyword search is used when a suitable model or vector is unavailable. Scans can contain OCR errors.")
            Text("The local preview is ad-hoc signed and not notarized. The stored library is not encrypted by the app. FileVault and your Mac account protect it at the operating-system level.")
                .foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.font(.system(size: 13)).lineSpacing(4).padding(35).frame(width: 570)
    }
}

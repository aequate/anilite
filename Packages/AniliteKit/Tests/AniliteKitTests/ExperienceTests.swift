import XCTest
@testable import AniliteKit

final class ConciergeTests: XCTestCase {
    func testIntents() {
        if case .define(let t) = Concierge.interpret("what is isekai") { XCTAssertEqual(t.term.lowercased(), "isekai") } else { XCTFail() }
        if case .define(let t) = Concierge.interpret("What does tsundere mean?") { XCTAssertEqual(t.term.lowercased(), "tsundere") } else { XCTFail() }
        XCTAssertEqual(Concierge.interpret("where do i start with monogatari"), .whereToStart(franchise: "Monogatari"))
        XCTAssertEqual(Concierge.interpret("watch order for fate"), .watchOrder(franchise: "Fate"))
        XCTAssertEqual(Concierge.interpret("anime like death note"), .findSimilar(title: "Death Note"))
        XCTAssertEqual(Concierge.interpret("can I skip filler in naruto?"), .fillerQuestion(franchise: "Naruto"))
        XCTAssertEqual(Concierge.interpret("does bleach have filler"), .fillerQuestion(franchise: "Bleach"))
        XCTAssertEqual(Concierge.interpret("what should i watch next"), .whatNext)
        XCTAssertEqual(Concierge.interpret("hello"), .greeting)
        XCTAssertEqual(Concierge.interpret(""), .greeting)
        if case .beginnerPicks(let topics) = Concierge.interpret("I'm new to anime, something funny") {
            XCTAssertTrue(topics.contains("comedy"))
        } else { XCTFail() }
        XCTAssertEqual(Concierge.interpret("Cowboy Bebop"), .search("Cowboy Bebop"))
    }

    func testGlossaryAndGateway() {
        XCTAssertNotNil(Glossary.lookup("OVA"))
        XCTAssertNotNil(Glossary.lookup("ova"))
        XCTAssertNil(Glossary.lookup("zzzz"))
        XCTAssertFalse(Glossary.mentioned(in: "This OVA is a filler arc").isEmpty)
        XCTAssertGreaterThanOrEqual(Glossary.terms.count, 30)
        XCTAssertEqual(Set(Glossary.terms.map { $0.term.lowercased() }).count, Glossary.terms.count, "Glossary terms are unique")

        let comedy = Gateway.picks(matching: ["comedy"])
        XCTAssertFalse(comedy.isEmpty)
        XCTAssertTrue(comedy.allSatisfy { $0.tags.contains("comedy") })
        XCTAssertEqual(Gateway.picks(matching: []).count, 4)
        XCTAssertEqual(Set(Gateway.picks.map(\.id)).count, Gateway.picks.count)
    }

    func testStartAdviceForAoT() throws {
        let batch = try Fixture.decode(MediaBatchResponse.self, "relations")
        var graph = FranchiseGraph(seed: batch.Page.media[0])
        for m in batch.Page.media { graph.merge(m) }
        let advice = Concierge.startAdvice(graph: graph)
        XCTAssertTrue(advice.hasPrefix("Start with"))
        XCTAssertTrue(advice.contains("alternate version"))
    }
}

final class StreamingTests: XCTestCase {
    func frieren() throws -> Media { try Fixture.decode(MediaResponse.self, "detail").Media }

    func testUSOptions() throws {
        let options = StreamingResolver.options(for: try frieren(), region: "US")
        let sites = options.map(\.site)
        XCTAssertFalse(sites.contains("Twitter"))
        XCTAssertFalse(sites.contains("Official Site"))
        XCTAssertEqual(options.first { $0.site == "Crunchyroll" }?.availability, .serviceInRegion)
        XCTAssertEqual(options.first { $0.site == "Hulu" }?.availability, .serviceInRegion)
        if case .regionalChannel(let label)? = options.first(where: { $0.site == "YouTube" })?.availability {
            XCTAssertTrue(label.contains("Muse Asia"))
        } else { XCTFail("YouTube Muse Asia should be a regional channel") }
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
        // In-region services are listed before anything uncertain.
        let firstUncertain = options.firstIndex { $0.availability != .serviceInRegion } ?? options.count
        XCTAssertTrue(options[firstUncertain...].allSatisfy { $0.availability != .serviceInRegion })
    }

    func testOtherRegionsAndUnknown() throws {
        let india = StreamingResolver.options(for: try frieren(), region: "IN")
        XCTAssertEqual(india.first { $0.site == "Hulu" }?.availability, .serviceNotInRegion)
        XCTAssertFalse(india.first { $0.site == "Hulu" }?.isLikelyAvailable ?? true)
        let nowhere = StreamingResolver.options(for: try frieren(), region: nil)
        XCTAssertTrue(nowhere.allSatisfy { $0.availability != .serviceNotInRegion })
    }
}

final class AtmosphereTests: XCTestCase {
    func testModesFollowGenre() {
        XCTAssertEqual(Atmosphere.resolve(for: makeMedia(1, "Mech", genres: ["Mecha"])).mode, .stars)
        XCTAssertEqual(Atmosphere.resolve(for: makeMedia(2, "Ball", genres: ["Sports"])).mode, .speed)
        XCTAssertEqual(Atmosphere.resolve(for: makeMedia(3, "Calm", genres: ["Slice of Life"])).mode, .motes)
        XCTAssertEqual(Atmosphere.resolve(for: makeMedia(4, "Love", genres: ["Romance"])).mode, .petals)
        XCTAssertEqual(Atmosphere.resolve(for: makeMedia(5, "Fear", genres: ["Horror"])).mode, .abyss)
        XCTAssertEqual(Atmosphere.resolve(for: makeMedia(6, "Plain")).mode, .aurora)
        let a = Atmosphere.resolve(for: makeMedia(7, "Fight", genres: ["Action"]))
        XCTAssertEqual(a.mode, .embers)
        XCTAssertTrue((0...1).contains(a.energy) && (0...1).contains(a.density))
    }

    func testPaletteIsReadableOnDark() throws {
        let palette = ArtworkPalette.from(hex: "#bbf1a1")
        XCTAssertGreaterThanOrEqual(palette.accent.contrast(with: palette.deep), 4.5)
        let dark = ArtworkPalette.from(hex: "#1a0a2e")
        XCTAssertGreaterThanOrEqual(dark.accent.contrast(with: dark.deep), 4.5)
        XCTAssertEqual(ArtworkPalette.from(hex: nil), .fallback)
        XCTAssertEqual(RGB(hex: "#ff8000")?.hex, "#FF8000")
        XCTAssertNil(RGB(hex: "nope"))
        let hsl = try XCTUnwrap(RGB(hex: "#3366cc")).hsl
        XCTAssertEqual(hsl.rgb.hex, "#3366CC")
    }

    func testSwatchesFindDominantVividColor() {
        let red = RGB(r: 0.85, g: 0.1, b: 0.1)
        let grey = RGB(r: 0.5, g: 0.5, b: 0.5)
        let pixels = Array(repeating: red, count: 300) + Array(repeating: grey, count: 200) + Array(repeating: RGB.black, count: 50)
        let swatches = PaletteExtractor.swatches(pixels)
        XCTAssertFalse(swatches.isEmpty)
        let top = swatches[0].color
        XCTAssertGreaterThan(top.r, top.g + 0.4)
        let palette = ArtworkPalette.from(pixels: pixels)
        XCTAssertGreaterThan(palette.accent.r, palette.accent.b)
    }
}

final class AtlasTests: XCTestCase {
    func testExpandDetailBuildsRichGraph() throws {
        let frieren = try Fixture.decode(MediaResponse.self, "detail").Media
        var graph = AtlasGraph()
        graph.expand(media: frieren)
        let kinds = Set(graph.nodeList.map(\.id.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.anime, .character, .studio, .theme]))
        XCTAssertTrue(graph.nodes[AtlasNodeID(.studio, 11)] != nil, "MADHOUSE")
        XCTAssertFalse(graph.neighbors(of: AtlasNodeID(.anime, frieren.id)).isEmpty)
        XCTAssertLessThanOrEqual(graph.nodes.count, graph.maxNodes)
        // Edges only connect nodes that exist.
        XCTAssertTrue(graph.edges.allSatisfy { graph.nodes[$0.a] != nil && graph.nodes[$0.b] != nil })

        let countBefore = graph.nodes.count
        graph.expand(media: frieren)
        XCTAssertEqual(graph.nodes.count, countBefore, "Expanding twice is idempotent")
    }

    func testLayoutSettlesDeterministically() throws {
        let frieren = try Fixture.decode(MediaResponse.self, "detail").Media
        var graph = AtlasGraph()
        graph.expand(media: frieren)
        var a = ForceLayout(), b = ForceLayout()
        a.sync(with: graph); b.sync(with: graph)
        a.settle(graph: graph); b.settle(graph: graph)
        XCTAssertTrue(a.isSettled)
        XCTAssertEqual(a.positions.count, graph.nodes.count)
        XCTAssertTrue(a.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        let id = AtlasNodeID(.anime, frieren.id)
        XCTAssertEqual(a.positions[id]!.x, b.positions[id]!.x, accuracy: 1e-9)

        var flat = ForceLayout()
        flat.flat = true
        flat.sync(with: graph)
        flat.settle(graph: graph)
        XCTAssertTrue(flat.positions.values.allSatisfy { abs($0.z) < 1e-6 })
    }

    func testCameraProjection() {
        var camera = AtlasCamera()
        let center = camera.project(.zero)
        XCTAssertNotNil(center)
        XCTAssertEqual(center?.x ?? 99, 0, accuracy: 1e-6)
        let before = camera.distance
        camera.zoom(by: 2)
        XCTAssertLessThan(camera.distance, before)
        camera.orbit(dx: 50, dy: 10_000)
        XCTAssertLessThanOrEqual(abs(camera.pitch), Double.pi / 2)
    }
}

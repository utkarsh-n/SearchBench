import LocalSearchKit

enum SyntheticCorpus {
    struct Fixture: Sendable {
        let id: String
        let title: String
        let text: String
        let query: String
    }

    static let fixtures = [
        Fixture(id: "capacitor", title: "Charge on capacitor plates",
            text: "A capacitor stores electrical energy in an electric field between two conducting plates separated by an insulator. Capacitance is charge divided by voltage, C = Q / V. Raising voltage increases stored energy, E = C V squared / 2. The dielectric stops direct current between the plates.",
            query: "how is electrical charge stored between insulated plates"),
        Fixture(id: "pressure", title: "A sharp needle creates pressure",
            text: "Pressure is force divided by area, P = F / A. A needle's narrow tip concentrates the same push into a smaller contact patch and raises pressure. Snowshoes spread a person's weight across a larger area and reduce sinking into soft snow. Force is measured in newtons and pressure in pascals.",
            query: "why does a narrow point pierce more easily under the same push"),
        Fixture(id: "orbits", title: "Gravity and falling around a planet",
            text: "A satellite in orbit continually falls toward Earth while moving sideways quickly enough to miss the surface. Gravity provides the inward acceleration that bends its path. For a circular orbit, v squared / r = G M / r squared. A higher orbit has a longer period and a lower circular speed.",
            query: "why does a satellite keep falling without hitting the planet"),
        Fixture(id: "strings", title: "Vibrating guitar strings and pitch",
            text: "A plucked guitar string vibrates and transfers motion into the body and surrounding air, creating sound. The fundamental frequency rises when tension increases or vibrating length decreases. Standing wave harmonics occur at integer multiples of the fundamental. A heavier string has a lower pitch at the same length and tension.",
            query: "what changes the pitch of a plucked musical string"),
        Fixture(id: "garden", title: "Sunlight feeds green leaves",
            text: "Green plants use sunlight in photosynthesis to turn water and carbon dioxide into sugars and release oxygen. Chlorophyll in leaves absorbs light. A seedling in darkness cannot make enough new sugar and may grow pale while spending stored food. Water roots carefully and give young plants sufficient light.",
            query: "why do young green plants need illumination to make food"),
        Fixture(id: "plumbing", title: "Repair a leaking water pipe",
            text: "A leaking pipe beneath a sink can leave the cabinet wet. Turn off the water supply before loosening the fitting. Replace the worn seal or tighten the joint carefully, then restore water and inspect for drips. A drain trap holds water to prevent sewer gas from entering the room.",
            query: "what should I do before fixing a dripping pipe under a sink"),
        Fixture(id: "battery", title: "Chemical energy inside a battery",
            text: "A rechargeable battery stores energy chemically. During discharge, reactions at its electrodes push electrons through an external circuit. A charger drives the reverse reaction and restores stored chemical energy. Capacity is expressed in ampere hours; approximate energy in watt hours is capacity times nominal voltage.",
            query: "how does a rechargeable cell store and deliver energy"),
        Fixture(id: "attention", title: "A transformer selects relevant tokens",
            text: "Transformer attention compares each query vector with key vectors to decide which tokens matter for the current position. A softmax turns scaled dot products into weights, and a weighted sum of value vectors forms the output. Multiple attention heads learn different relationships between words. Attention weights are neither probabilities of truth nor a complete explanation of a model.",
            query: "how does a transformer weigh the relevant words in a sequence")
    ]

    static func documents(count: Int) -> [LocalSearchDocument] {
        var docs = fixtures.map {
            LocalSearchDocument(id: $0.id, title: $0.title, segments: [.text($0.text)],
                                metadata: ["fixture": "target", "corpus": "synthetic-v1"])
        }
        let subjects = ["pottery", "weaving", "cartography", "baking", "calligraphy", "bookbinding", "woodworking", "ceramics", "origami", "embroidery", "printmaking", "basketry"]
        let materials = ["clay", "linen", "paper", "flour", "ink", "thread", "oak", "porcelain", "bamboo", "cotton", "pigment", "willow"]
        for index in 0..<max(0, count - docs.count) {
            let subject = subjects[index % subjects.count]
            let material = materials[(index * 5 + 3) % materials.count]
            let batch = index + 1
            let text = "Workshop record \(batch) describes \(subject) practice with \(material). The maker sorts supplies, measures the pattern, and checks the finish. This sample uses \(batch % 7 + 2) pieces and a labeled storage shelf. Keep the workspace orderly, compare the result with the template, and record each step for the next session."
            docs.append(LocalSearchDocument(id: "filler-\(index)", title: "\(subject.capitalized) workshop \(batch)",
                segments: [.text(text)], metadata: ["fixture": "distractor", "corpus": "synthetic-v1"]))
        }
        return docs
    }

    /// 25 distinct inputs ensure the unique-query series never repeats an identical query.
    static let uniqueQueries: [(String, String)] = fixtures.map { ($0.query, $0.id) } + [
        ("why does changing plate voltage change stored field energy", "capacitor"),
        ("why do snowshoes prevent a person sinking deeply into snow", "pressure"),
        ("how can a spacecraft stay in a circular path around Earth", "orbits"),
        ("why does tightening a guitar string make its note higher", "strings"),
        ("how do leaves turn light and carbon dioxide into sugar", "garden"),
        ("how can I stop water dripping from the fitting beneath a washbasin", "plumbing"),
        ("what does a charger reverse inside a rechargeable battery", "battery"),
        ("what are query key and value vectors doing in attention", "attention"),
        ("what insulates the conductors in a capacitor", "capacitor"),
        ("how can spreading weight over more surface reduce pressure", "pressure"),
        ("what supplies the inward acceleration of an orbiting satellite", "orbits"),
        ("how do standing waves create musical overtones on a string", "strings"),
        ("what happens to a seedling that has no sunlight", "garden"),
        ("why should the water supply be turned off before a pipe repair", "plumbing"),
        ("why does stored chemical energy drive electrons through a circuit", "battery"),
        ("how does softmax combine value vectors from important tokens", "attention"),
        ("why do higher circular orbits take longer to complete", "orbits")
    ]
}

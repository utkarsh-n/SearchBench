import Foundation

@main struct MeasurementTests {
    static func main() {
        let fifty = LatencySummary((1...50).map(Double.init))
        precondition(fifty.count == 50 && fifty.medianMilliseconds == 25 && fifty.p95Milliseconds == 48)
        precondition(fifty.meanMilliseconds == 25.5 && fifty.minMilliseconds == 1 && fifty.maxMilliseconds == 50)
        let unordered = LatencySummary([10, 0, 8, 4, 2])
        precondition(unordered.medianMilliseconds == 4 && unordered.p95Milliseconds == 10)
        let invalid = LatencySummary([.nan, .infinity, -2])
        precondition(invalid.count == 0 && invalid.p95Milliseconds == 0)
        precondition(LatencySummary([19]).medianMilliseconds == 19)
        let correct = QueryMeasurement(query: "test", expectedID: "expected", milliseconds: 5,
            hitIDs: ["wrong", "expected"], topCosine: 0.8)
        precondition(correct.expectedInTopFive == true && correct.expectedAtRankOne == false)
        let tooLow = QueryMeasurement(query: "test", expectedID: "expected", milliseconds: 5,
            hitIDs: ["a", "b", "c", "d", "e", "expected"], topCosine: 0.8)
        precondition(tooLow.expectedInTopFive == false)
        let memory = MemorySampler.readMemory()
        precondition((memory.footprint ?? 0) > 0 && (memory.resident ?? 0) > 0)
        precondition((memory.kernelPeak ?? 0) >= (memory.footprint ?? 0))
        print("Measurement assertions passed: nearest-rank P50/P95, filtering, top-5 correctness, real Mach footprint/RSS/lifetime peak.")
    }
}

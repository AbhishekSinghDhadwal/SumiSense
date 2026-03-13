import XCTest
@testable import SumiSenseCore

final class SumiSenseCoreTests: XCTestCase {
    func testRuleBasedAnalyzerDetectsElevatedSignals() {
        let note = "Barely slept and thought about using again. I felt anxious all day."
        let result = RuleBasedAnalyzer.assess(note)

        XCTAssertEqual(result.0, .elevated)
        XCTAssertTrue(result.1.contains("sleep disruption"))
        XCTAssertTrue(result.1.contains("craving language"))
    }

    func testTrendHeuristicDetectsWorsening() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let metrics = [
            WellnessMetricPoint(date: formatter.date(from: "2026-03-01")!, sleepHours: 7.4, moodScore: 6.7, stressScore: 3.0, cravingScore: 1.0, energyScore: 6.2),
            WellnessMetricPoint(date: formatter.date(from: "2026-03-02")!, sleepHours: 7.3, moodScore: 6.6, stressScore: 3.2, cravingScore: 1.0, energyScore: 6.1),
            WellnessMetricPoint(date: formatter.date(from: "2026-03-03")!, sleepHours: 5.6, moodScore: 5.0, stressScore: 5.8, cravingScore: 2.9, energyScore: 4.1),
            WellnessMetricPoint(date: formatter.date(from: "2026-03-04")!, sleepHours: 5.2, moodScore: 4.7, stressScore: 6.4, cravingScore: 3.6, energyScore: 3.7),
            WellnessMetricPoint(date: formatter.date(from: "2026-03-05")!, sleepHours: 5.0, moodScore: 4.3, stressScore: 6.8, cravingScore: 4.0, energyScore: 3.4),
            WellnessMetricPoint(date: formatter.date(from: "2026-03-06")!, sleepHours: 4.9, moodScore: 4.1, stressScore: 7.1, cravingScore: 4.5, energyScore: 3.1)
        ]

        let result = TrendHeuristicAnalyzer.analyze(metrics: metrics, windowDays: 3)
        XCTAssertEqual(result.direction, .worsening)
    }

    func testRegexRedactorMasksSensitiveFields() {
        let input = "My name is Maya. Email me at maya@demo.com or call 602-555-1901 on 03/10/2026."
        let output = RegexRedactor.redact(input, mode: .researchSafe)

        XCTAssertTrue(output.transformed.contains("[Email]"))
        XCTAssertTrue(output.transformed.contains("[Phone]"))
        XCTAssertTrue(output.transformed.contains("[Date]"))
    }
}

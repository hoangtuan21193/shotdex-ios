import Foundation
import SwiftUI

/// Loads all Statistics aggregates for the selected date scope.
@MainActor
@Observable
final class StatsController {
    private let statsDAO: StatsDAO

    var scope: StatsDateScope = .allTime {
        didSet { if scope != oldValue { load() } }
    }

    private(set) var summary: StatsSummary = .empty
    private(set) var cameraUsage: [UsageCount] = []
    private(set) var lensUsage: [UsageCount] = []
    private(set) var sensorFormatUsage: [UsageCount] = []
    /// Photos missing the field, split out of the lists above — shown only
    /// as a section footnote, not as an "Unknown" row/slice.
    private(set) var cameraUnknownCount = 0
    private(set) var lensUnknownCount = 0
    private(set) var sensorUnknownCount = 0
    private(set) var focalHistogramActual: [HistogramBucket] = []
    private(set) var focalHistogramEquivalent: [HistogramBucket] = []
    private(set) var isoHistogram: [HistogramBucket] = []
    private(set) var isoStats: (mostCommon: Double?, average: Double?, median: Double?) = (nil, nil, nil)
    private(set) var apertureHistogram: [HistogramBucket] = []
    private(set) var apertureMostCommon: Double?
    private(set) var shutterHistogram: [HistogramBucket] = []
    private(set) var shutterMostCommon: Double?
    private(set) var slowShutterShare: Double?
    private(set) var cameraTrend: [StatsDAO.MonthlyCount] = []
    /// Photos without a capture date — excluded from every non-all-time scope.
    private(set) var undatedCount = 0
    /// Oldest capture date in the index — bounds the custom range picker.
    private(set) var earliestDate: Date?
    private(set) var isLoading = false

    init(dependencies: AppDependencies) {
        self.statsDAO = dependencies.statsDAO
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        summary = (try? statsDAO.summary(scope: scope)) ?? .empty
        (cameraUsage, cameraUnknownCount) = Self.splitUnknown((try? statsDAO.cameraUsage(scope: scope)) ?? [])
        (lensUsage, lensUnknownCount) = Self.splitUnknown((try? statsDAO.lensUsage(scope: scope)) ?? [])
        (sensorFormatUsage, sensorUnknownCount) = Self.splitUnknown((try? statsDAO.sensorFormatUsage(scope: scope)) ?? [])
        focalHistogramActual = (try? statsDAO.focalLengthHistogram(equivalent: false, scope: scope)) ?? []
        focalHistogramEquivalent = (try? statsDAO.focalLengthHistogram(equivalent: true, scope: scope)) ?? []

        isoHistogram = (try? statsDAO.rangeHistogram(
            column: "iso",
            groups: ISOQuickGroup.allCases.map { ($0.rawValue, $0.range) },
            scope: scope
        )) ?? []
        isoStats = (try? statsDAO.valueStats(column: "iso", scope: scope)) ?? (nil, nil, nil)

        apertureHistogram = (try? statsDAO.rangeHistogram(
            column: "aperture",
            groups: ApertureQuickGroup.allCases.map { ($0.rawValue, $0.range) },
            scope: scope
        )) ?? []
        apertureMostCommon = (try? statsDAO.valueStats(column: "aperture", scope: scope))?.mostCommon

        shutterHistogram = (try? statsDAO.rangeHistogram(
            column: "shutterSpeedSeconds",
            groups: ShutterQuickGroup.allCases.map { ($0.rawValue, $0.range) },
            scope: scope
        )) ?? []
        shutterMostCommon = (try? statsDAO.valueStats(column: "shutterSpeedSeconds", scope: scope))?.mostCommon
        slowShutterShare = try? statsDAO.slowShutterShare(scope: scope)

        cameraTrend = (try? statsDAO.cameraMonthlyTrend(topBodies: 3, scope: scope)) ?? []
        undatedCount = (try? statsDAO.undatedCount()) ?? 0
        earliestDate = try? statsDAO.earliestCreationDate()
    }

    /// The DAO appends a synthetic "Unknown" bucket for photos missing the
    /// field; pull it out so the UI can show the count as a footnote instead.
    private static func splitUnknown(_ usage: [UsageCount]) -> ([UsageCount], Int) {
        var known: [UsageCount] = []
        var unknownCount = 0
        for entry in usage {
            if entry.isUnknown {
                unknownCount += entry.count
            } else {
                known.append(entry)
            }
        }
        return (known, unknownCount)
    }
}

//
//  Correlation.swift
//  Fastino
//
//  Least squares and Pearson r, with the guardrails that stop thirty noisy days
//  from being presented as a finding (§4.8).
//
//  Deliberately domain-free: it knows about `(x, y)` and nothing about fasts,
//  sleep or weight. The pairings live in `Shared/Health/HealthCorrelation.swift`
//  and the wording lives there too, so both are testable without a view.
//
//  Two refusals are built in rather than left to the caller, because a caller
//  that forgets them draws a confident line through noise:
//
//  - **Too few points.** Under `minimumSample`, `fit` returns nil.
//  - **No spread in x.** Every point on one vertical line has no slope to
//    report, and the r formula divides by zero getting there.
//

import Foundation

nonisolated enum Correlation {

    /// Below this many paired observations there is nothing worth fitting.
    /// Eight is not a statistical threshold so much as an honesty one — it's
    /// roughly a week and a bit of data, the point at which a user would start
    /// to expect the app to have noticed something.
    static let minimumSample = 8

    /// Below this |r|, report no direction. A weak correlation on this much
    /// self-reported data is indistinguishable from none.
    static let meaningfulR = 0.2

    struct LinearFit: Equatable, Sendable {
        let slope: Double
        let intercept: Double
        /// Pearson correlation coefficient, -1...1.
        let r: Double
        let n: Int

        /// Whether `r` is far enough from zero to describe a direction.
        var isMeaningful: Bool { abs(r) >= meaningfulR }

        func y(at x: Double) -> Double { slope * x + intercept }
    }

    /// Group means either side of a threshold — what the headline sentence
    /// quotes, because "25 minutes more" is readable and "r = 0.41" is not.
    struct Split: Equatable, Sendable {
        let belowMean: Double
        let aboveMean: Double
        let belowCount: Int
        let aboveCount: Int

        /// How much higher the *below-threshold* group's y is. Positive means
        /// doing the thing earlier/less went with a higher y.
        var difference: Double { belowMean - aboveMean }
    }

    static func fit(_ pairs: [(x: Double, y: Double)]) -> LinearFit? {
        guard pairs.count >= minimumSample else { return nil }

        let n = Double(pairs.count)
        let meanX = pairs.reduce(0) { $0 + $1.x } / n
        let meanY = pairs.reduce(0) { $0 + $1.y } / n

        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for pair in pairs {
            let dx = pair.x - meanX
            let dy = pair.y - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }

        // No spread in x — nothing to fit. No spread in y is a real answer
        // (a flat line, r = 0), but the r formula can't produce it, so it's
        // refused here too rather than returning a NaN.
        guard varianceX > 0, varianceY > 0 else { return nil }

        let slope = covariance / varianceX
        return LinearFit(
            slope: slope,
            intercept: meanY - slope * meanX,
            r: covariance / (varianceX * varianceY).squareRoot(),
            n: pairs.count
        )
    }

    /// Mean y either side of `threshold`. Nil unless *both* groups have at
    /// least two members — a comparison against a single night isn't one.
    static func split(_ pairs: [(x: Double, y: Double)], at threshold: Double) -> Split? {
        let below = pairs.filter { $0.x < threshold }
        let above = pairs.filter { $0.x >= threshold }
        guard below.count >= 2, above.count >= 2 else { return nil }

        return Split(
            belowMean: below.reduce(0) { $0 + $1.y } / Double(below.count),
            aboveMean: above.reduce(0) { $0 + $1.y } / Double(above.count),
            belowCount: below.count,
            aboveCount: above.count
        )
    }
}

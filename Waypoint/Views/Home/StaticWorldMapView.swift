import Foundation
import SwiftUI
import WebKit

struct StaticWorldMapView: UIViewRepresentable {
    let visitedCountryCodes: [String]
    let plannedCountryCodes: [String]

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isAccessibilityElement = false
        webView.accessibilityElementsHidden = true

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let normalizedVisitedCodes = visitedCountryCodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { $0.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil }
            .sorted()
        let visitedCodeSet = Set(normalizedVisitedCodes)
        let normalizedPlannedCodes = plannedCountryCodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { $0.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil }
            .filter { !visitedCodeSet.contains($0) }
            .sorted()

        let renderVersion = "svg-raw-v1"
        let cacheKey = renderVersion + "|visited=" + normalizedVisitedCodes.joined(separator: ",") + "|planned=" + normalizedPlannedCodes.joined(separator: ",")
        guard cacheKey != context.coordinator.lastRenderedKey else { return }
        context.coordinator.lastRenderedKey = cacheKey

        guard let svgURL = Bundle.main.url(forResource: "world_map", withExtension: "svg"),
              let rawSVG = try? String(contentsOf: svgURL, encoding: .utf8) else {
            webView.loadHTMLString(missingSVGHTML, baseURL: nil)
            return
        }

        let normalizedSVG = normalizedRootSVG(rawSVG)
        webView.loadHTMLString(
            htmlWrapper(
                svg: normalizedSVG,
                visitedCodes: normalizedVisitedCodes,
                plannedCodes: normalizedPlannedCodes
            ),
            baseURL: nil
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func highlightRule(for highlightedCodes: [String], fillVariable: String, strokeVariable: String, shadowVariable: String) -> String {
        guard !highlightedCodes.isEmpty else { return "" }
        let selectors = highlightedCodes.map { "svg path#\($0)" }.joined(separator: ", ")
        return """
        \(selectors) {
          fill: var(\(fillVariable)) !important;
          stroke: var(\(strokeVariable)) !important;
          stroke-width: 1.6 !important;
          opacity: 1 !important;
          filter: drop-shadow(0 0 4px var(\(shadowVariable)));
        }
        """
    }

    private func normalizedRootSVG(_ svg: String) -> String {
        let hasViewBox = svg.range(
            of: "<svg\\b[^>]*\\bviewBox\\s*=",
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        let width = extractNumericAttribute("width", in: svg) ?? 1009.6727
        let height = extractNumericAttribute("height", in: svg) ?? 665.96301

        let injected = hasViewBox
            ? "<svg preserveAspectRatio=\"xMidYMid meet\""
            : "<svg viewBox=\"0 0 \(width) \(height)\" preserveAspectRatio=\"xMidYMid meet\""

        guard let regex = try? NSRegularExpression(pattern: "<svg\\b", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: svg, options: [], range: NSRange(svg.startIndex..., in: svg)),
              let range = Range(match.range, in: svg) else {
            return svg
        }

        return svg.replacingCharacters(in: range, with: injected)
    }

    private func extractNumericAttribute(_ attribute: String, in svg: String) -> Double? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: attribute))=\\\"([0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: svg, options: [], range: NSRange(svg.startIndex..., in: svg)),
              let range = Range(match.range(at: 1), in: svg) else {
            return nil
        }
        return Double(svg[range])
    }

    private func htmlWrapper(svg: String, visitedCodes: [String], plannedCodes: [String]) -> String {
        let plannedCSS = highlightRule(
            for: plannedCodes,
            fillVariable: "--planned-fill",
            strokeVariable: "--planned-stroke",
            shadowVariable: "--planned-shadow"
        )
        let visitedCSS = highlightRule(
            for: visitedCodes,
            fillVariable: "--visited-fill",
            strokeVariable: "--visited-stroke",
            shadowVariable: "--visited-shadow"
        )

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            :root {
              --country-fill: #7b8fb4;
              --country-stroke: #bdcceb;
              --visited-fill: #ff9500;
              --visited-stroke: #dc6803;
              --visited-shadow: rgba(255, 149, 0, 0.65);
              --planned-fill: #ff453a;
              --planned-stroke: #d70015;
              --planned-shadow: rgba(255, 69, 58, 0.58);
            }

            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              overflow: hidden;
            }

            .map-wrapper {
              width: 100%;
              height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
            }

            .map-wrapper > svg {
              width: 100% !important;
              height: 100% !important;
              display: block;
              background: transparent;
            }

            svg path[id] {
              fill: var(--country-fill) !important;
              stroke: var(--country-stroke) !important;
              stroke-width: 1.05 !important;
              stroke-linejoin: round;
              stroke-linecap: round;
              opacity: 1 !important;
              visibility: visible !important;
              shape-rendering: geometricPrecision;
            }

            \(plannedCSS)
            \(visitedCSS)

            @media (prefers-color-scheme: dark) {
              :root {
                --country-fill: #6d84ae;
                --country-stroke: #c3d3f3;
                --visited-fill: #ffb347;
                --visited-stroke: #ff9500;
                --visited-shadow: rgba(255, 179, 71, 0.85);
                --planned-fill: #ff6961;
                --planned-stroke: #ff453a;
                --planned-shadow: rgba(255, 105, 97, 0.8);
              }
            }
          </style>
        </head>
        <body>
          <div class="map-wrapper">\(svg)</div>
        </body>
        </html>
        """
    }

    private var missingSVGHTML: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body {
              margin: 0;
              display: flex;
              align-items: center;
              justify-content: center;
              width: 100vw;
              height: 100vh;
              background: transparent;
              color: #475569;
              font: 600 14px -apple-system, BlinkMacSystemFont, sans-serif;
            }
          </style>
        </head>
        <body>world_map.svg was not found in the app bundle.</body>
        </html>
        """
    }

    final class Coordinator {
        var lastRenderedKey: String = ""
    }
}

#Preview {
    StaticWorldMapView(
        visitedCountryCodes: ["US", "PT", "JP"],
        plannedCountryCodes: ["IS", "AR"]
    )
        .frame(height: 240)
        .padding()
        .background(PlannerBackgroundView())
}

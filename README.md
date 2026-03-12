# Waypoint

Waypoint is the public repository for **BeLocal**, an iOS travel companion focused on personalized destination discovery, city exploration, and AI-assisted trip planning.

![BeLocal logo](Waypoint/Resources/logo.svg)

## Overview

BeLocal combines local-first travel data, personalized ranking, and AI-assisted planning in a single SwiftUI app. The product is built for travelers who want suggestions that feel grounded in budget, seasonality, sustainability, and local perspective instead of generic “top destinations” lists.

## What the app does

- Builds a travel profile through onboarding and uses it to rank destinations.
- Recommends destinations with explainable scoring, CO2 estimates, and style matching.
- Lets users explore cities on a map, browse attractions, and read traveler/local feedback.
- Generates planning conversations and final travel briefs through an AI planner workflow.
- Stores user state locally with SwiftData and syncs authenticated data with Supabase.
- Supports multilingual UX and adaptive fallbacks when online services are unavailable.

## Product highlights

- **Personalized recommendation engine** powered by CoreML, explicit preference signals, and explainability layers.
- **City Explorer** built with MapKit, live enrichment, and feedback translation.
- **Planner Studio** with conversational planning, saved conversations, and final brief generation.
- **Hybrid AI stack** using Apple Foundation Models when available and OpenAI-backed services where needed.
- **Offline-aware architecture** with local persistence, queued sync operations, and network monitoring.

## Tech stack

- Swift
- SwiftUI
- SwiftData
- CoreML
- MapKit
- Foundation Models
- Supabase REST/Auth
- OpenAI Responses API
- Google Places API
- Geoapify

## Repository structure

```text
Waypoint/
├── Waypoint/                  # App source, resources, models, services, and views
├── Waypoint.xcodeproj/        # Xcode project
├── .github/                   # Issue and pull request templates
├── docs/                      # Public project documentation
├── README.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
└── LICENSE
```

## Getting started

### Prerequisites

- macOS with full Xcode installed
- Xcode 26.3 or newer recommended
- iOS Simulator or physical device matching the project deployment target
- Optional service accounts for Supabase, OpenAI, Google Places, and Geoapify

### Local setup

1. Open [`Waypoint.xcodeproj`](Waypoint.xcodeproj) in Xcode.
2. Fill the placeholder values in:
   - [`Waypoint/Resources/SupabaseConfig.plist`](Waypoint/Resources/SupabaseConfig.plist)
   - [`Waypoint/Resources/TravelAPIConfig.plist`](Waypoint/Resources/TravelAPIConfig.plist)
3. Alternatively, configure runtime environment variables in your Xcode scheme as documented in [`docs/setup.md`](docs/setup.md).
4. Run the `Waypoint` target.

## Public repository notes

- This repository is prepared for public sharing with placeholder configuration values only.
- User-specific Xcode files and local build artifacts are ignored.
- If secrets were ever committed in previous local history, rotate them before publishing the remote repository.

## Contributing

Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

## Security

If you discover a vulnerability or an exposed credential, follow [`SECURITY.md`](SECURITY.md).

## License

This project is released under the MIT License. See [`LICENSE`](LICENSE).

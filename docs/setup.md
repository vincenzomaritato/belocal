# Local Setup

## Xcode

- Use the full Xcode app, not Command Line Tools only.
- Open the `Waypoint.xcodeproj` project and run the `Waypoint` target.

## Configuration files

The repository keeps only placeholder values in committed config files:

- `Waypoint/Resources/SupabaseConfig.plist`
- `Waypoint/Resources/TravelAPIConfig.plist`

Fill those placeholders locally before running features that require external services.

## Supported environment variables

You can also define these in your Xcode scheme:

### Supabase

- `SUPABASE_PROJECT_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_ANON_KEY`
- `SUPABASE_TRIPS_TABLE`
- `SUPABASE_FEEDBACK_TABLE`
- `SUPABASE_ACTIVITIES_TABLE`
- `SUPABASE_PROFILES_TABLE`

### Travel and AI services

- `GOOGLE_PLACES_API_KEY`
- `GOOGLE_MAPS_API_KEY`
- `GEOAPIFY_API_KEY`
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `DEFAULT_ORIGIN_IATA`

## Publishing checklist

- Keep committed plist files on placeholder values.
- Rotate any credential that was previously committed to local history before publishing a remote.
- Verify `.gitignore` still excludes user-specific Xcode data and local artifacts.


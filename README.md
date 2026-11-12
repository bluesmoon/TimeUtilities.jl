# TimeUtilities

[![Build Status](https://github.com/bluesmoon/TimeUtilities.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/bluesmoon/TimeUtilities.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage Status](https://coveralls.io/repos/github/bluesmoon/TimeUtilities.jl/badge.svg?branch=main)](https://coveralls.io/github/bluesmoon/TimeUtilities.jl?branch=main)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://bluesmoon.github.io/TimeUtilities.jl/)

## Introduction

`TimeUtilities` is a Julia module providing utilities for working with dates, times, and timezones to fill some convenience gaps
left in the standard Dates and TimeZones modules.

In particular, it
- adds a `Base.trunc` method to truncate a `DateTime` to the start of the week,
  which is the only deterministic variant missing in `Dates.jl`
- adds ZonedDateTime constructors for `FixedTimeZone` that accept and discard a
  DST ambiguity parameter. The constructors in `TimeZones.jl` do not accept the DST
  ambiguity parameter for `FixedTimeZones` thus making it hard to implement generic
  code that does not require slow exception handling.

This module also includes
- code to parse dates and times with and without timezones from strings using a series
  of common formats, iterating through the list till it finds a match,
- Convenience functions to convert to and from epoch milliseconds,
- A `NormalizedTimeType` container struct that can hold multiple representations of a time value,
- Types for representing time windows, which are tuples of two `TimeType`s or two `NormalizedTimeType`s,
- and a function to convert `LEGACY` timezone abbreviations to the most likely matching standard timezone
  name, with a fallback to UTC for unrecognized abbreviations.


`TimeUtilities.jl` is distributed under the MIT License. See [LICENSE](LICENSE) for details and is compatible
with Julia 1.6 and later. Its only dependencies are the built-in `Dates` module and the standard `TimeZones` modules.

All functions and types are documented.

### Exported Types
- `NormalizedTimeType`,
- `TimeWindowType`,
- `NormalizedTimeWindowType`

### Exported Functions
- `normalizeTimestamps`,
- `timestampToZonedDateTime`,
- `datetime2ms`,
- `ms2datetime`,
- `expand_legacy_timezone`,
- `astimezone`

**NOTE:** This module makes guesses about intended values when datetimes end up invalid due to a daylight saving time transition.
The standard libraries throw an exception in these cases. Make sure that this behavior is acceptable for your use case.

## Quick Start

```julia
using TimeUtilities, Dates, TimeZones

# Create a normalized time from a DateTime
t1 = NormalizedTimeType(DateTime(2016, 10, 10, 1, 2, 3))

# Create a normalized time with a specific timezone
t2 = NormalizedTimeType(DateTime(2016, 10, 10, 1, 2, 3), tz"America/New_York")

# Access different representations
t2.timeUTC          # UTC DateTime
t2.timeTZ           # ZonedDateTime
t2.timeMS           # Milliseconds since epoch
t2.timezone         # TimeZone

# Normalize multiple timestamps at once
timestamps = normalizeTimestamps(
    DateTime(2016, 10, 10, 1, 2, 3),
    Date(2015, 4, 3),
    ZonedDateTime(DateTime(2016, 10, 10), tz"America/New_York")
)

# Parse flexible timestamp strings
tz = tz"America/New_York"
zdt1 = timestampToZonedDateTime("2016-10-10 12:30:45", tz)
zdt2 = timestampToZonedDateTime("2016-10-10T12:30:45.123+0500", tz"UTC")
```

## Usage Examples

We have a few examples below, but you can also look through the tests for more examples.

### Working with NormalizedTimeType

`NormalizedTimeType` provides a unified container for working with time in multiple formats:

```julia
julia> using TimeUtilities, Dates, TimeZones

julia> t = NormalizedTimeType(Date(2016, 10, 10))
TimeUtilities.NormalizedTimeType(UTC,2016-10-10T00:00:00,2016-10-10T00:00:00+00:00,1476057600000)

# Use as DateTime
julia> convert(DateTime, t)
2016-10-10T00:00:00

# Use as ZonedDateTime
julia> convert(ZonedDateTime, t)
2016-10-10T00:00:00+00:00

# Use as milliseconds
julia> convert(Int64, t)
1476057600000

# Perform arithmetic with Periods
julia> t + Month(1) - Day(2)
TimeUtilities.NormalizedTimeType(UTC,2016-11-08T00:00:00,2016-11-08T00:00:00+00:00,1478563200000)
```

### Timezone Conversion

```julia
julia> # Start with a UTC DateTime
julia> dt = DateTime(2016, 10, 10, 1, 2, 3)

# Convert to New York time
julia> ny_tz = tz"America/New_York"
julia> t_ny = NormalizedTimeType(dt, ny_tz)
TimeUtilities.NormalizedTimeType(America/New_York (UTC-5/UTC-4),2016-10-10T05:02:03,2016-10-10T01:02:03-04:00,1476075723000)

# The UTC time stays the same
julia> t_ny.timeUTC
2016-10-10T01:02:03

# But the local representation reflects the timezone
julia> t_ny.timeTZ
2016-10-10T01:02:03-04:00
```

### Parsing Flexible Timestamp Formats

The module recognizes multiple timestamp formats:

```julia
julia> using TimeUtilities, TimeZones

julia> tz = tz"UTC"

# Space-separated format
julia> timestampToZonedDateTime("2016-10-10 12:30:45", tz)
2016-10-10T12:30:45+00:00

# ISO 8601 T-separator
julia> timestampToZonedDateTime("2016-10-10T12:30:45", tz)
2016-10-10T12:30:45+00:00

# With milliseconds
julia> timestampToZonedDateTime("2016-10-10T12:30:45.123", tz)
2016-10-10T12:30:45.123+00:00

# With timezone offset (compact format)
julia> timestampToZonedDateTime("2016-10-10T12:30:45+0530", tz"UTC")
2016-10-10T12:30:45+05:30

# With timezone offset (colon-separated)
julia> timestampToZonedDateTime("2016-10-10T12:30:45-05:00", tz"UTC")
2016-10-10T12:30:45-05:00
```

### Normalizing Multiple Timestamps

Process multiple timestamps with a common timezone reference:

```julia
julia> using TimeUtilities, Dates, TimeZones

# Normalize with explicit timezone
julia> norms = normalizeTimestamps("America/New_York",
           DateTime(2016, 10, 10, 1, 2, 3),
           Date(2015, 4, 3)
       )
2-element Vector{NormalizedTimeType}:
 NormalizedTimeType(America/New_York,2016-10-10T05:02:03,2016-10-10T01:02:03-04:00,1476075723000)
 NormalizedTimeType(America/New_York,2015-04-03T04:00:00,2015-04-03T00:00:00-04:00,1428033600000)

# Access converted form via broadcasting
julia> convert.(DateTime, norms)
2-element Vector{DateTime}:
 2016-10-10T05:02:03
 2015-04-03T04:00:00
```

### Converting Between Representations

```julia
julia> using TimeUtilities, Dates

# DateTime to milliseconds since epoch
julia> ms = datetime2ms(DateTime(2016, 10, 10, 1, 2, 3))
1476061323000

# Milliseconds back to DateTime
julia> ms2datetime(1476061323000)
2016-10-10T01:02:03

# Using with ZonedDateTime
julia> using TimeZones
julia> zdt = ZonedDateTime(DateTime(2016, 10, 10, 1, 2, 3), tz"America/New_York")
2016-10-10T01:02:03-04:00

julia> datetime2ms(zdt)
1476075723000
```

### Handling Legacy Timezone Abbreviations

```julia
julia> using TimeUtilities, TimeZones

# Resolve common abbreviations to full timezone names
julia> expand_legacy_timezone("EST")
America/New_York

julia> expand_legacy_timezone("PST")
America/Los_Angeles

julia> expand_legacy_timezone("JST")
Asia/Tokyo

# Unrecognized abbreviations default to UTC
julia> expand_legacy_timezone("XYZ")
UTC
```

### Truncating to Specific Time Periods

```julia
julia> using TimeUtilities, Dates

# Truncate a NormalizedTimeType to a specific period
julia> t = NormalizedTimeType(DateTime(2016, 10, 10, 15, 47, 23))

# Truncate to the start of the week (Monday)
julia> trunc(t, Week)
NormalizedTimeType(UTC,2016-10-10T00:00:00,2016-10-10T00:00:00+00:00,1476057600000)

# Truncate to the start of the day
julia> trunc(t, Day)
NormalizedTimeType(UTC,2016-10-10T00:00:00,2016-10-10T00:00:00+00:00,1476057600000)

# Truncate to the start of the hour
julia> trunc(t, Hour)
NormalizedTimeType(UTC,2016-10-10T15:00:00,2016-10-10T15:00:00+00:00,1476099600000)
```

## Core Types & Functions

### `NormalizedTimeType`

A container that normalizes time values into multiple representations for convenient access:

- **Fields:**
  - `tz::TimeZone` — The timezone of the time value
  - `timeUTC::DateTime` — UTC representation
  - `timeTZ::ZonedDateTime` — Timezone-aware representation
  - `timeMS::Int64` — Milliseconds since Unix epoch (1970-01-01T00:00:00Z)

- **Converters:** Can be converted to `DateTime`, `ZonedDateTime`, or `Int64`
- **Operators:** Supports addition/subtraction with `Period` types
- **Comparison:** Supports `==`, `<`, and other comparison operators

### `DATE_FORMATS`

Regex patterns and formats for parsing timezone-naïve timestamps. Supports:
- `yyyy-mm-dd HH:MM:SS[.sss]` (space-separated)
- `yyyy-mm-ddTHH:MM:SS[.sss]` (ISO 8601)

### `DATE_FORMATS_TZ`

Regex patterns and formats for parsing timezone-aware timestamps with numeric offsets. Supports:
- Compact offset: `±HHMM` (e.g., `+0400`)
- Colon-separated offset: `±HH:MM` (e.g., `-05:30`)
- Space-separated offset: ` HHMM` (e.g., ` 0400`)

### Key Functions

- **`NormalizedTimeType(t::TimeType, [tz::Union{TimeZone,AbstractString}])`** — Create a normalized time container
- **`normalizeTimestamps(t..., [tz])`** — Normalize multiple timestamps
- **`timestampToZonedDateTime(d, tz)`** — Parse and convert to ZonedDateTime (works with DateTime, Date, or string)
- **`datetime2ms(dt)`** — Convert DateTime/Date/ZonedDateTime to milliseconds since epoch
- **`ms2datetime(ms)`** — Convert milliseconds since epoch to DateTime
- **`expand_legacy_timezone(tz_str)`** — Resolve timezone abbreviations to full names
- **`astimezone(dt::DateTime, tz::TimeZone=tz"UTC")`** — Convert DateTime to ZonedDateTime in specified timezone

## Advanced Features

### DST Handling

The module automatically handles daylight saving time transitions. When converting to a timezone where the local time is ambiguous or doesn't exist:

```julia
julia> using TimeUtilities, TimeZones

# During DST transition, 2:30 AM doesn't exist in America/New_York
# (clocks jump from 1:59:59 EST to 3:00:00 EDT on 2020-03-08)
julia> dt = DateTime(2020, 3, 8, 2, 30, 0)
julia> timestampToZonedDateTime(dt, tz"America/New_York")
2020-03-08T01:30:00-05:00  # Automatically adjusted to most likely intended valid time
```

### Vectorized Operations

Use broadcasting to apply timezone conversion to multiple timestamps:

```julia
julia> using TimeUtilities, Dates, TimeZones

julia> dates = [
    DateTime(2016, 10, 10),
    DateTime(2016, 10, 11),
    DateTime(2016, 10, 12)
]

julia> tz = tz"America/New_York"

# Convert all dates to the timezone
julia> converted = timestampToZonedDateTime.(dates, tz)
3-element Vector{ZonedDateTime}:
 2016-10-10T00:00:00-04:00
 2016-10-11T00:00:00-04:00
 2016-10-12T00:00:00-04:00
```

## See Also

- [Dates.jl Documentation](https://docs.julialang.org/en/v1/stdlib/Dates/)
- [TimeZones.jl Documentation](https://timezonesjl.readthedocs.io/)

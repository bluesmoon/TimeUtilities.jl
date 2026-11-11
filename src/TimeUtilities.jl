"""
    TimeUtilities

A Julia module providing utilities for working with dates, times, and timezones to fill some convenience gaps
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

"""
module TimeUtilities

using Dates, TimeZones

import TimeZones: astimezone, ZonedDateTime

export
    NormalizedTimeType,
    TimeWindowType,
    NormalizedTimeWindowType,
    datetime2ms,
    ms2datetime,
    astimezone,
    timestampToZonedDateTime,
    normalizeTimestamps,
    expand_legacy_timezone

"""
Ordered list of `(Regex, DateFormat)` pairs for parsing timezone-naïve date/time strings.

Each entry matches a specific string pattern and provides the corresponding `Dates.DateFormat`
to parse it into a `DateTime`. Patterns are tried in order; the first match wins.

Supported formats:
- `yyyy-mm-dd HH:MM:SS[.sss]`   — space separator, optional milliseconds
- `yyyy-mm-ddTHH:MM:SS[.sss]`   — ISO 8601 T separator, optional milliseconds
- `yyyy-mm-ddTHH:MM:SS[.sss]+`  — trailing `+` sentinel (offset stripped by caller)
- `yyyy-mm-ddTHH:MM:SS[.sss]-`  — trailing `-` sentinel (offset stripped by caller)

Used by [`timestampToZonedDateTime`](@ref) for strings without a numeric timezone offset.
For timezone-aware strings see [`DATE_FORMATS_TZ`](@ref).
"""
const DATE_FORMATS = [
    (r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{0,3})?$", Dates.DateFormat("y-m-d H:M:S.s")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{0,3})?$", Dates.DateFormat("y-m-dTH:M:S.s")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{1,3}\+$"   , Dates.DateFormat("y-m-dTH:M:S.s+")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{1,3}\-$"   , Dates.DateFormat("y-m-dTH:M:S.s-")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+$"            , Dates.DateFormat("y-m-dTH:M:S+")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\-$"            , Dates.DateFormat("y-m-dTH:M:S-")),
]


"""
Ordered list of `(Regex, DateFormat)` pairs for parsing date/time strings that embed a
numeric timezone offset.

Each entry matches a specific timezone-aware pattern and provides the corresponding
`Dates.DateFormat` to parse it into a `ZonedDateTime`. Patterns are tried in order;
the first match wins.

Supported offset formats (combined with both T-separator and space-separator date-time):
- `±HHMM`   — compact offset, e.g. `+0400`
- `±HH:MM`  — colon-separated offset, e.g. `-05:30`
- ` HHMM`   — space-separated offset, e.g. ` 0400`

Milliseconds are optional in all patterns.

Used by [`timestampToZonedDateTime`](@ref) for timezone-aware strings.
For timezone-naïve strings see [`DATE_FORMATS`](@ref).
"""
const DATE_FORMATS_TZ = [
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{1,3}[+-]\d{4}$"    , Dates.DateFormat("y-m-dTH:M:SS.sz")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$", Dates.DateFormat("yyyy-mm-ddTHH:MM:SS.ssszzzz")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{1,3} \d{4}$"       , Dates.DateFormat("y-m-dTH:M:SS.s z")),
    (r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,3}[+-]\d{4}$"    , Dates.DateFormat("y-m-d H:M:SS.sz")),
    (r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,3} \d{4}$"       , Dates.DateFormat("y-m-d H:M:SS.s z")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}$"             , Dates.DateFormat("y-m-dTH:M:SSz")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$"       , Dates.DateFormat("y-m-dTH:M:SSzzzz")),
    (r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[+-]\d{4}$"             , Dates.DateFormat("y-m-d H:M:SSz")),
    (r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$"       , Dates.DateFormat("y-m-d H:M:SSzzzz")),
    (r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} \d{4}$"                , Dates.DateFormat("y-m-dTH:M:SS z")),
    (r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \d{4}$"                , Dates.DateFormat("y-m-d H:M:SS z")),
]

"""
Convert a `TimeType` to milliseconds from the epoch
"""
datetime2ms(dt::DateTime)                       = round(Int, datetime2unix(dt) * 1000)
datetime2ms(dt::Date)                           = datetime2ms(DateTime(dt))
datetime2ms(dt::ZonedDateTime)                  = datetime2ms(dt.utc_datetime)

"""
Create a `DateTime` from milliseconds from the epoch
"""
ms2datetime(ms::Int64)                          = unix2datetime(ms/1000)

"""
Converts a `DateTime` to a `ZonedDateTime` in the specified timezone assuming the `DateTime` is in `UTC`.
"""
astimezone(dt::DateTime, tz::TimeZone=tz"UTC")  = astimezone(ZonedDateTime(dt, tz"UTC"), tz)

# Allow passing of dst ambiguity parameter to `FixedTimeZone` calls where it's discarded
ZonedDateTime(y::Integer, m::Integer, d::Integer, h::Integer, mi::Integer, s::Integer, ms::Integer, tz::FixedTimeZone, amb::Integer) = ZonedDateTime(y, m, d, h, mi, s, ms, tz)
ZonedDateTime(y::Integer, m::Integer, d::Integer, h::Integer, mi::Integer, s::Integer, tz::FixedTimeZone, amb::Integer) = ZonedDateTime(y, m, d, h, mi, s, tz)
ZonedDateTime(y::Integer, m::Integer, d::Integer, h::Integer, mi::Integer, tz::FixedTimeZone, amb::Integer) = ZonedDateTime(y, m, d, h, mi, tz)
ZonedDateTime(y::Integer, m::Integer, d::Integer, h::Integer, tz::FixedTimeZone, amb::Integer) = ZonedDateTime(y, m, d, h, tz)
ZonedDateTime(y::Integer, m::Integer, d::Integer, tz::FixedTimeZone, amb::Integer) = ZonedDateTime(y, m, d, tz)
ZonedDateTime(y::Integer, m::Integer, tz::FixedTimeZone, amb::Integer) = ZonedDateTime(y, m, tz)
ZonedDateTime(y::Integer, tz::FixedTimeZone, amb::Integer) = ZonedDateTime(y, tz)
ZonedDateTime(dt::DateTime, tz::FixedTimeZone, is_dst::Bool) = ZonedDateTime(dt, tz)
ZonedDateTime(dt::DateTime, tz::FixedTimeZone, occurrence::Integer) = ZonedDateTime(dt, tz)

"""
A container type for various views of a given `TimeType` which, via converters, may be used as a `TimeType` itself.

* `struct NormalizedTimeType`

#### Fields

`tz::TimeZone`
: The `TimeZone` of the contained `TimeType`. `timezone` is an alias of this field to make it a drop-in replacement for `ZonedDateTime`.

`timeUTC::DateTime`
: The `UTC` converted representation of the contained `TimeType`. `utc_datetime` is an alias of this field to make it a drop-in replacement for `ZonedDateTime`.

`timeTZ::ZonedDateTime`
: A `ZonedDateTime` representing the contained `TimeType` and its `TimeZone`

`timeMS::Int64`
: The contained `TimeType` represented as milliseconds since the Unix Epoch of 1970-01-01T00:00:00.000Z

#### Constructors

`NormalizedTimeType(::TimeType)`
: Constructs a `NormalizedTimeType` from a `TimeType`. The passed in `TimeType` may be a `Date`, a `DateTime`, a `ZonedDateTime`, or any other subtype of `TimeType`

`NormalizedTimeType(::TimeType, ::TimeZone|AbstractString)`
: Constructs a `NormalizedTimeType` from a `DateTime` with an associated `TimeZone`.  The second parameter may either be a `TimeZone` object or a string TimeZone name.

#### Converters

`NormalizedTimeType` has converters for `DateTime`, `ZonedDateTime`, and `Int64`, so it may be used wherever one of these three types is required.

#### Operators

You may also add and subtract any `Dates.Period` or `Dates.CompoundPeriod` to/from a `NormalizedTimeType` object to get a new `NormalizedTimeType` object.

For example:

```julia
julia> t1 = NormalizedTimeType(Date(2016, 10, 10))
TimeUtilities.NormalizedTimeType(UTC,2016-10-10T00:00:00,2016-10-10T00:00:00+00:00,1476057600000)

julia> t1 + Dates.Month(1) - Dates.Day(2)
TimeUtilities.NormalizedTimeType(UTC,2016-11-08T00:00:00,2016-11-08T00:00:00+00:00,1478563200000)

julia> t1 - Dates.Month(1) + Dates.Week(1)
TimeUtilities.NormalizedTimeType(UTC,2016-09-17T00:00:00,2016-09-17T00:00:00+00:00,1474070400000)
```


#### Examples
```julia
julia> NormalizedTimeType(Date(2016, 10, 10))
TimeUtilities.NormalizedTimeType(UTC,2016-10-10T00:00:00,2016-10-10T00:00:00+00:00,1476057600000)
```

```julia
julia> NormalizedTimeType(DateTime(2016, 10, 10, 1, 2, 3))
TimeUtilities.NormalizedTimeType(UTC,2016-10-10T01:02:03,2016-10-10T01:02:03+00:00,1476061323000)
```

```julia
julia> NormalizedTimeType(ZonedDateTime(DateTime(2016, 10, 10, 1, 2, 3), tz"America/New_York"))
TimeUtilities.NormalizedTimeType(America/New_York (UTC-5/UTC-4),2016-10-10T05:02:03,2016-10-10T05:02:03-04:00,1476075723000)
```

```julia
julia> NormalizedTimeType(DateTime(2016, 10, 10, 1, 2, 3), tz"America/New_York")
TimeUtilities.NormalizedTimeType(America/New_York (UTC-5/UTC-4),2016-10-10T05:02:03,2016-10-10T05:02:03-04:00,1476075723000)
```

```julia
julia> NormalizedTimeType(DateTime(2016, 10, 10, 1, 2, 3), "America/New_York")
TimeUtilities.NormalizedTimeType(America/New_York (UTC-5/UTC-4),2016-10-10T05:02:03,2016-10-10T05:02:03-04:00,1476075723000)
```

#### See also
[`TimeUtilities.normalizeTimestamps`](@ref)
"""
struct NormalizedTimeType
    tz      :: TimeZone
    timeUTC :: DateTime
    timeTZ  :: ZonedDateTime
    timeMS  :: Int64

    # Compatibility with ZonedDateTime to make this a drop-in replacement
    utc_datetime :: DateTime
    timezone     :: TimeZone

    function NormalizedTimeType(t::TimeType, tz::TimeZone=tz"UTC")
        if isa(t, ZonedDateTime)
            tz      = t.timezone
            timeUTC = t.utc_datetime
            timeTZ  = t
        else
            timeTZ  = ZonedDateTime(DateTime(t), tz, 1)
            timeUTC = timeTZ.utc_datetime
        end
        timeMS = datetime2ms(timeUTC)

        new(tz, timeUTC, timeTZ, timeMS, timeUTC, tz)
    end

    NormalizedTimeType(t::TimeType, tz::AbstractString) = NormalizedTimeType(t, TimeZone(tz))
    NormalizedTimeType(t::NormalizedTimeType, x...) = t
end

import Base: +, -, ==, convert, isless

convert(::Type{DateTime}, x::NormalizedTimeType) = x.timeUTC
convert(::Type{ZonedDateTime}, x::NormalizedTimeType) = x.timeTZ
convert(::Type{Int64}, x::NormalizedTimeType) = x.timeMS
convert(::Type{DateTime}, zdt::ZonedDateTime) = zdt.utc_datetime + zdt.zone.offset

-(ntt::NormalizedTimeType, p::Union{Dates.CompoundPeriod, Dates.Period}) = NormalizedTimeType(ntt.timeTZ - p)
+(ntt::NormalizedTimeType, p::Union{Dates.CompoundPeriod, Dates.Period}) = NormalizedTimeType(ntt.timeTZ + p)
-(t1::NormalizedTimeType, t2::NormalizedTimeType) = t1.timeUTC - t2.timeUTC
==(x::NormalizedTimeType, y::NormalizedTimeType) = x.timeMS == y.timeMS && x.tz == y.tz
isless(x::NormalizedTimeType, y::NormalizedTimeType) = isless(x.timeMS, y.timeMS)

datetime2ms(normalizedTimeType::NormalizedTimeType) = normalizedTimeType.timeMS

"""
Normalize multiple `TimeType`s to `NormalizedTimeType`s

* `normalizeTimestamps(t...) → NormalizedTimeType[...]`
* `normalizeTimestamps(tz, t...) → NormalizedTimeType[...]`

`TimeType` is the common supertype for `DateTime`, `Date`, `ZonedDateTime` and others.

#### Arguments
`tz::AbstractString|TimeZone`
: [optional] The common timezone to use for all `t`s that don't have their own TimeZone

`t::TimeType...`
: The time values to normalize.

#### Returns
An array of [`NormalizedTimeType`](@ref)

#### Example

```julia
julia> norms = TimeUtilities.normalizeTimestamps(
           DateTime(2016, 10, 10, 1, 2, 3),
           ZonedDateTime(DateTime(2016, 10, 10), TimeZone("America/New_York")),
           Date(2015, 4, 3)
       )
3-element Array{TimeUtilities.NormalizedTimeType,1}:
 TimeUtilities.NormalizedTimeType(UTC,2016-10-10T01:02:03,2016-10-10T01:02:03+00:00,1476061323000)
 TimeUtilities.NormalizedTimeType(America/New_York (UTC-5/UTC-4),2016-10-10T04:00:00,2016-10-10T04:00:00-04:00,1476072000000)
 TimeUtilities.NormalizedTimeType(UTC,2015-04-03T00:00:00,2015-04-03T00:00:00+00:00,1428019200000)
```

```julia
julia> norms = TimeUtilities.normalizeTimestamps("America/New_York", DateTime(2016, 10, 10, 1, 2, 3), Date(2015, 4, 3))
2-element Array{TimeUtilities.NormalizedTimeType,1}:
 TimeUtilities.NormalizedTimeType(America/New_York (UTC-5/UTC-4),2016-10-10T05:02:03,2016-10-10T01:02:03-04:00,1476075723000)
 TimeUtilities.NormalizedTimeType(America/New_York (UTC-5/UTC-4),2015-04-03T04:00:00,2015-04-03T00:00:00-04:00,1428033600000)
```
"""
normalizeTimestamps(t::Union{NormalizedTimeType,TimeType}...) = NormalizedTimeType[NormalizedTimeType(x) for x in t]
normalizeTimestamps(tz::Union{TimeZone, AbstractString}, t::Union{NormalizedTimeType,TimeType}...) = NormalizedTimeType[NormalizedTimeType(x, tz) for x in t]


"""
* `timestampToZonedDateTime(::DateTime, ::TimeZone)` → `ZonedDateTime`
* `timestampToZonedDateTime(::Date, ::TimeZone)` → `ZonedDateTime`
* `timestampToZonedDateTime(::AbstractString, ::TimeZone)` → `ZonedDateTime`
* `timestampToZonedDateTime.(::Vector, ::TimeZone)` → `Vector{ZonedDateTime}`

Convert a compatible object to a `ZonedDateTime` with a specified `TimeZone`.

Any incompatible objects are returned as-is, which makes this suitable to call on Vectors of mixed types (such as `missing`).

If called on a `String`, will check [`DATE_FORMATS`](@ref) and [`DATE_FORMATS_TZ`](@ref) for a suitable parser.

If the object represents a timestamp that isn't valid in the specified timezone, then this function will attempt to determine
the most appropriate value by checking the delta with the DST transition, applying that to the UTC equivalent, and then converting.

Use the broadcast operator to apply this to a Vector.
"""
timestampToZonedDateTime(d::Any, tz::TimeZone) = d
timestampToZonedDateTime(d::Date, tz::TimeZone) = timestampToZonedDateTime(DateTime(d), tz)
function timestampToZonedDateTime(d::DateTime, tz::TimeZone)
    try
        return ZonedDateTime(d, tz, 1)
    catch ex
        !isa(ex, NonExistentTimeError) && rethrow()

        # NonExistentTimeError happens when as a result of truncation and rounding we end up with a date that doesn't exist
        # in a particular timezone.  eg: 2020-03-08T02:00:00 in tz"America/New_York" (since we go from 01:59:59 EST to 03:00:00 EDT)
        # What we do is, check how far off this is from the nearest DST transition, we then subtract that value from the UTC representation
        # of the DST transition to get the UTC representation of our intended time. We can then convert this to local time and come up
        # with a reasonable value
        local undef, mindex = findmin([abs(t.utc_datetime + t.zone.offset.std + t.zone.offset.dst - ex.local_dt) for t in ex.timezone.transitions])
        local t = ex.timezone.transitions[mindex]
        return astimezone(ZonedDateTime(ex.local_dt - t.zone.offset.std - t.zone.offset.dst, tz"UTC"), ex.timezone)
    end
end
function timestampToZonedDateTime(d::AbstractString, tz::TimeZone)
    # Check if it's in a known format without a timezone
    for (re, fmt) in DATE_FORMATS
        if occursin(re, d)
            return timestampToZonedDateTime(DateTime(d, fmt), tz)
        end
    end

    # Check if it's in a known format with a timezone
    for (re, fmt) in DATE_FORMATS_TZ
        if occursin(re, d)
            return ZonedDateTime(d, fmt)
        end
    end

    # Check if the caller appends Z to Date object
    if occursin("Z", d)
        d = replace(d, "Z" => "")
        return timestampToZonedDateTime(DateTime(d), tz)
    end

    @warn("No match for $d, returning a string")

    # No match, just return it
    return d
end


"""
Internal dictionary of common legacy timezone abbreviations to their full TimeZone names.

We use this dictionary because timezones_from_abbr returns multiple results that all
match the offset of the common abbreviation. Rather than pick a random one, we use the
most likely candidate based on colloquial usage. For example, "EST" is used in multiple
timezones, but the most common usage is "America/New_York".  This dictionary is used to
disambiguate these cases.

Used by [`expand_legacy_timezone`](@ref).
"""
const common_tz_abbrs = Dict(
    "EST" => tz"America/New_York",
    "EDT" => tz"America/New_York",
    "CST" => tz"America/Chicago",
    "CDT" => tz"America/Chicago",
    "MST" => tz"America/Denver",
    "MDT" => tz"America/Denver",
    "PST" => tz"America/Los_Angeles",
    "PDT" => tz"America/Los_Angeles",
    "GMT" => tz"Europe/London",
    "BST" => tz"Europe/London",
    "CET" => tz"Europe/Paris",
    "CEST" => tz"Europe/Paris",
    "EET" => tz"Europe/Helsinki",
    "EEST" => tz"Europe/Helsinki",
    "JST" => tz"Asia/Tokyo",
    "AEST" => tz"Australia/Sydney",
    "AEDT" => tz"Australia/Sydney",
    "ACST" => tz"Australia/Adelaide",
    "ACDT" => tz"Australia/Adelaide",
    "AWST" => tz"Australia/Perth",
    "IST" => tz"Asia/Kolkata",
    "KST" => tz"Asia/Seoul",
    "MSK" => tz"Europe/Moscow",
    "NZST" => tz"Pacific/Auckland",
    "NZDT" => tz"Pacific/Auckland",
    "HST" => tz"Pacific/Honolulu",
    "AKST" => tz"America/Anchorage",
    "AKDT" => tz"America/Anchorage",
    "AST" => tz"America/Halifax",
    "ADT" => tz"America/Halifax",
    "WET" => tz"Europe/Lisbon",
    "WEST" => tz"Europe/Lisbon",
    "ART" => tz"America/Argentina/Buenos_Aires",
    "BRT" => tz"America/Sao_Paulo",
    "CLT" => tz"America/Santiago",
    "CLST" => tz"America/Santiago",
    "EAT" => tz"Africa/Nairobi",
    "SAST" => tz"Africa/Johannesburg",
    "WAT" => tz"Africa/Lagos",
    "WAST" => tz"Africa/Windhoek",
    "AST" => tz"America/Caracas",
    "ADT" => tz"America/Caracas",
    "COT" => tz"America/Bogota",
    "PET" => tz"America/Lima",
    "VET" => tz"America/Caracas"
)

"""
Convert a legacy TimeZone abbreviation to a full TimeZone name.  If the TimeZone is not recognized, will return UTC.
"""
function expand_legacy_timezone(tz_str::AbstractString)
    if isempty(tz_str)
        tz_str = tz"UTC"
    elseif tz_str ∈ timezone_abbrs()
        old_str = tz_str
        tz_str = get(common_tz_abbrs, tz_str, timezones_from_abbr(tz_str)[ceil(Int, end/2)])
        if tz_str.name != old_str
            @warn("Received an abbreviated TimeZone: $old_str, using full timezone: $tz_str instead.")
        end
    elseif tz_str ∉ timezone_names()
        @warn("Received an unrecognized TimeZone: $tz_str, falling back to UTC.")
        tz_str = tz"UTC"
    end
    if isa(tz_str, TimeZone)
        tz = tz_str
    else
        tz = TimeZone(tz_str, TimeZones.Class(:ALL))
    end

    return tz
end

### Add `Base.trunc` for DateTime & Week.  Other DatePeriods are implemented for all TimeType.
### Docs are in Base julia
### We truncate to Day, and then subtract the number of days in the week, except 1 because julia weeks start on Sunday while database weeks start on Monday
Base.trunc(dt::DateTime, ::Type{Dates.Week}) = trunc(dt, Day) - Day(dayofweek(dt) - 1)

### Add `Base.trunc` for NormalizedTimeType
Base.trunc(dt::NormalizedTimeType, t::Type{<:Dates.Period}) = NormalizedTimeType(trunc(dt.timeTZ, t))

const TimeWindowType = Tuple{<:TimeType, <:TimeType}
const NormalizedTimeWindowType = Tuple{NormalizedTimeType, NormalizedTimeType}

end

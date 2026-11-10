using TimeUtilities, Test, Dates, TimeZones
import TimeUtilities: datetime2ms, ms2datetime, NormalizedTimeType, normalizeTimestamps, timestampToZonedDateTime

@testset "datetime" begin
    @test datetime2ms(DateTime(2020, 3, 4, 12, 34, 56, 789)) == 1583325296789
    @test datetime2ms(Date(2020, 3, 4)) == 1583280000000
    @test datetime2ms(ZonedDateTime(2020, 3, 4, 12, 34, 56, 789, tz"America/New_York")) == 1583343296789
    @test datetime2ms(ZonedDateTime(2020, 3, 4, 12, 34, 56, 789, tz"America/New_York")) == datetime2ms(DateTime(2020, 3, 4, 12, 34, 56, 789)) + (5 * 60 * 60 * 1000) # UTC-05:00
    @test DateTime(2020, 3, 4, 12, 34, 56, 789) == ms2datetime(1583325296789)

    @test ZonedDateTime(DateTime(2021, 10, 31, 2), tz"UTC", 1) == ZonedDateTime(2021, 10, 31, 2, tz"UTC")

    @test ZonedDateTime(2020, 3, 8, 1, tz"America/New_York") == timestampToZonedDateTime("2020-03-08T01:00:00", tz"America/New_York")
    @test ZonedDateTime(2020, 3, 8, 1, tz"America/New_York") == timestampToZonedDateTime("2020-03-08T02:00:00", tz"America/New_York")
    @test ZonedDateTime(2020, 3, 8, 1, 10, tz"America/New_York") == timestampToZonedDateTime("2020-03-08T02:10:00", tz"America/New_York")
    @test ZonedDateTime(2020, 3, 8, 3, tz"America/New_York") == timestampToZonedDateTime("2020-03-08T03:00:00", tz"America/New_York")
    @test ZonedDateTime(2020, 3, 8, tz"America/New_York") == timestampToZonedDateTime(Date(2020, 3, 8), tz"America/New_York")
    @test :FOOBAR == timestampToZonedDateTime(:FOOBAR, tz"America/New_York")
    @test_logs (:warn, "No match for FOOBAR, returning a string") (@test "FOOBAR" == timestampToZonedDateTime("FOOBAR", tz"America/New_York"))

    dateparts = [2024, 3, 6, 1, 2, 3, 4]
    @testset "ZonedDateTime $p" for p in 1:length(dateparts)
        @test ZonedDateTime(dateparts[1:p]..., tz"UTC") == ZonedDateTime(dateparts[1:p]..., tz"UTC", rand(-15:15))
    end
    @test ZonedDateTime(DateTime(2024, 3, 6), tz"UTC") == ZonedDateTime(DateTime(2024, 3, 6), tz"UTC", true)
    @test ZonedDateTime(DateTime(2024, 3, 6), tz"UTC") == ZonedDateTime(DateTime(2024, 3, 6), tz"UTC", false)

    @test DateTime(2024, 4, 15) == trunc(DateTime(2024, 4, 17), Dates.Week)
end


@testset "Legacy Time Zones" begin
    @test tz"UTC" == TimeUtilities.expand_legacy_timezone("")
    @test tz"America/New_York" == TimeUtilities.expand_legacy_timezone("America/New_York")
    @test tz"America/New_York" == (@test_logs (:warn, "Received an abbreviated TimeZone: EST, using full timezone: America/New_York instead.") TimeUtilities.expand_legacy_timezone("EST"))
    @test tz"UTC" == (@test_logs (:warn, "Received an unrecognized TimeZone: America/Old_York, falling back to UTC.") TimeUtilities.expand_legacy_timezone("America/Old_York"))
end


@testset "NormalizedTimeType" begin
    # NormalizedTimeType
    # 1. Simple Date object
    norm = NormalizedTimeType(Date(2016, 10, 10))
    @test norm.tz      == TimeZone("UTC")
    @test norm.timeUTC == DateTime(2016, 10, 10)
    @test norm.timeTZ  == ZonedDateTime(2016, 10, 10, TimeZone("UTC"))
    @test norm.timeMS  == 1476057600000
    @test datetime2ms(norm) == 1476057600000

    # 2. Simple DateTime object
    norm = NormalizedTimeType(DateTime(2016, 10, 10, 12, 34, 56, 789))
    @test norm.tz      == TimeZone("UTC")
    @test norm.timeUTC == DateTime(2016, 10, 10, 12, 34, 56, 789)
    @test norm.timeTZ  == ZonedDateTime(2016, 10, 10, 12, 34, 56, 789, TimeZone("UTC"))
    @test norm.timeMS  == 1476102896789

    # 3. ZonedDateTime object
    norm = NormalizedTimeType(ZonedDateTime(2016, 10, 10, 12, 34, 56, 789, TimeZone("America/New_York")))
    @test norm.tz      == TimeZone("America/New_York")
    @test norm.timeUTC == DateTime(2016, 10, 10, 16, 34, 56, 789)
    @test norm.timeTZ  == ZonedDateTime(2016, 10, 10, 12, 34, 56, 789, TimeZone("America/New_York"))
    @test norm.timeMS  == 1476117296789

    # Also test our ZonedDateTime compatibility fields
    @test norm.utc_datetime == DateTime(2016, 10, 10, 16, 34, 56, 789)
    @test norm.timezone  == TimeZone("America/New_York")

    # 4. DateTime & TimeZone
    norm = NormalizedTimeType(DateTime(2016, 10, 10, 12, 34, 56, 789), TimeZone("America/New_York"))
    @test norm.tz      == TimeZone("America/New_York")
    @test norm.timeUTC == DateTime(2016, 10, 10, 16, 34, 56, 789)
    @test norm.timeTZ  == ZonedDateTime(2016, 10, 10, 12, 34, 56, 789, TimeZone("America/New_York"))
    @test norm.timeMS  == 1476117296789

    # 4. DateTime & TimeZone String
    norm = NormalizedTimeType(DateTime(2016, 10, 10, 12, 34, 56, 789), "America/New_York")
    @test norm.tz      == TimeZone("America/New_York")
    @test norm.timeUTC == DateTime(2016, 10, 10, 16, 34, 56, 789)
    @test norm.timeTZ  == ZonedDateTime(2016, 10, 10, 12, 34, 56, 789, TimeZone("America/New_York"))
    @test norm.timeMS  == 1476117296789


    # normalizeTimestamps
    # 1. Simple DateTime objects

    norms = TimeUtilities.normalizeTimestamps(DateTime(2016, 10, 10), DateTime(2016, 10, 12))

    @test length(norms) == 2
    @test norms[1].tz      == TimeZone("UTC")
    @test norms[2].tz      == TimeZone("UTC")
    @test norms[1].timeUTC == DateTime(2016, 10, 10)
    @test norms[2].timeUTC == DateTime(2016, 10, 12)
    @test norms[1].timeMS  == 1476057600000
    @test norms[2].timeMS  == 1476230400000

    # 2. ZonedDateTime

    norms = TimeUtilities.normalizeTimestamps(
        ZonedDateTime(2016, 10, 10, TimeZone("America/New_York")),
        ZonedDateTime(2016, 10, 12, TimeZone("America/New_York"))
    )

    @test length(norms) == 2
    @test norms[1].tz      == TimeZone("America/New_York")
    @test norms[2].tz      == TimeZone("America/New_York")
    @test norms[1].timeUTC == DateTime(2016, 10, 10, 4)
    @test norms[2].timeUTC == DateTime(2016, 10, 12, 4)
    @test norms[1].timeMS  == 1476072000000
    @test norms[2].timeMS  == 1476244800000


    # 3. Mixed

    norms = TimeUtilities.normalizeTimestamps(
        ZonedDateTime(2016, 10, 10, TimeZone("America/New_York")),
        ZonedDateTime(2016, 10, 12, TimeZone("America/Los_Angeles"))
    )

    @test length(norms) == 2
    @test norms[1].tz      == TimeZone("America/New_York")
    @test norms[2].tz      == TimeZone("America/Los_Angeles")
    @test norms[1].timeUTC == DateTime(2016, 10, 10, 4)
    @test norms[2].timeUTC == DateTime(2016, 10, 12, 7)
    @test norms[1].timeMS  == 1476072000000
    @test norms[2].timeMS  == 1476255600000


    # 4. DST Boundary outer

    norms = TimeUtilities.normalizeTimestamps(
        ZonedDateTime(2016, 11, 6, 0, TimeZone("America/New_York")),
        ZonedDateTime(2016, 11, 6, 3, TimeZone("America/New_York"))
    )

    @test length(norms) == 2
    @test norms[1].tz      == TimeZone("America/New_York")
    @test norms[2].tz      == TimeZone("America/New_York")
    @test norms[1].timeUTC == DateTime(2016, 11, 6, 4)
    @test norms[2].timeUTC == DateTime(2016, 11, 6, 8)
    @test norms[1].timeMS  == 1478404800000
    @test norms[2].timeMS  == 1478419200000

    # 5. DST Boundary inner

    norms = TimeUtilities.normalizeTimestamps(
        ZonedDateTime(2016, 11, 6, 1, 30, TimeZone("America/New_York"), true),                   # true  == Daylight Time
        ZonedDateTime(2016, 11, 6, 1, 30, TimeZone("America/New_York"), false)                   # false == Standard Time
    )

    @test length(norms) == 2
    @test norms[1].tz      == TimeZone("America/New_York")
    @test norms[2].tz      == TimeZone("America/New_York")
    @test norms[1].timeUTC == DateTime(2016, 11, 6, 5, 30)
    @test norms[2].timeUTC == DateTime(2016, 11, 6, 6, 30)
    @test norms[1].timeMS  == 1478410200000
    @test norms[2].timeMS  == 1478413800000


    # 6. Mixed types
    norms = TimeUtilities.normalizeTimestamps(
        DateTime(2016, 10, 10, 1, 2, 3),
        ZonedDateTime(2016, 10, 10, TimeZone("America/New_York")),
        Date(2015, 4, 3)
    )

    @test length(norms) == 3
    @test norms[1].tz      == TimeZone("UTC")
    @test norms[2].tz      == TimeZone("America/New_York")
    @test norms[3].tz      == TimeZone("UTC")
    @test norms[1].timeUTC == DateTime(2016, 10, 10, 1, 2, 3)
    @test norms[2].timeUTC == DateTime(2016, 10, 10, 4, 0, 0)
    @test norms[3].timeUTC == DateTime(2015, 4, 3, 0, 0, 0)
    @test norms[1].timeMS  == 1476061323000
    @test norms[2].timeMS  == 1476072000000
    @test norms[3].timeMS  == 1428019200000

    # 7. Pass in an array
    dts = Dates.TimeType[
        DateTime(2016, 10, 10, 1, 2, 3),
        ZonedDateTime(2016, 10, 10, TimeZone("America/New_York")),
        Date(2015, 4, 3)
    ]
    norms = TimeUtilities.normalizeTimestamps(dts...)

    @test length(norms) == 3
    @test norms[1].tz      == TimeZone("UTC")
    @test norms[2].tz      == TimeZone("America/New_York")
    @test norms[3].tz      == TimeZone("UTC")
    @test norms[1].timeUTC == DateTime(2016, 10, 10, 1, 2, 3)
    @test norms[2].timeUTC == DateTime(2016, 10, 10, 4, 0, 0)
    @test norms[3].timeUTC == DateTime(2015, 4, 3, 0, 0, 0)
    @test norms[1].timeMS  == 1476061323000
    @test norms[2].timeMS  == 1476072000000
    @test norms[3].timeMS  == 1428019200000

    # 8. Pass in an array and timezone
    dts = Dates.TimeType[
        DateTime(2016, 10, 10, 1, 2, 3),
        ZonedDateTime(2016, 10, 10, TimeZone("America/New_York")),
        Date(2015, 4, 3)
    ]
    norms = TimeUtilities.normalizeTimestamps("America/Los_Angeles", dts...)

    @test length(norms) == 3
    @test norms[1].tz      == TimeZone("America/Los_Angeles")
    @test norms[2].tz      == TimeZone("America/New_York")
    @test norms[3].tz      == TimeZone("America/Los_Angeles")
    @test norms[1].timeUTC == DateTime(2016, 10, 10, 8, 2, 3)
    @test norms[2].timeUTC == DateTime(2016, 10, 10, 4, 0, 0)
    @test norms[3].timeUTC == DateTime(2015, 4, 3, 7, 0, 0)
    @test norms[1].timeMS  == 1476086523000
    @test norms[2].timeMS  == 1476072000000
    @test norms[3].timeMS  == 1428044400000

    # 9. Add/subtract Dates.Period
    norm1 = NormalizedTimeType(DateTime(2016, 10, 10, 12, 34, 56, 789), TimeZone("America/New_York"))
    # 9.1. DatePeriod Month
    norm2 = norm1 + Dates.Month(1)
    @test norm2.tz      == TimeZone("America/New_York")
    @test norm2.timeUTC == DateTime(2016, 11, 10, 17, 34, 56, 789) # DST boundary switch so 16 becomes 17
    @test norm2.timeTZ  == ZonedDateTime(2016, 11, 10, 12, 34, 56, 789, TimeZone("America/New_York"))
    @test norm2.timeMS  == 1478799296789

    # 9.2. DatePeriod Week
    norm2 = norm1 - Dates.Week(1)
    @test norm2.tz      == TimeZone("America/New_York")
    @test norm2.timeUTC == DateTime(2016, 10, 03, 16, 34, 56, 789)
    @test norm2.timeTZ  == ZonedDateTime(2016, 10, 03, 12, 34, 56, 789, TimeZone("America/New_York"))
    @test norm2.timeMS  == 1475512496789

    # 9.3. TimePeriod
    norm2 = norm1 + Dates.Hour(2)
    @test norm2.tz      == TimeZone("America/New_York")
    @test norm2.timeUTC == DateTime(2016, 10, 10, 18, 34, 56, 789)
    @test norm2.timeTZ  == ZonedDateTime(2016, 10, 10, 14, 34, 56, 789, TimeZone("America/New_York"))
    @test norm2.timeMS  == 1476124496789

    # 9.4. CompoundPeriod
    # We enclose the periods in parentheses to make it a CompoundPeriod, else left associativity of + & - will result in `norm1 + Dates.Hour(2)` being evaluated first
    norm2 = norm1 + (Dates.Hour(2) - Dates.Week(1))
    @test norm2.tz      == TimeZone("America/New_York")
    @test norm2.timeUTC == DateTime(2016, 10, 3, 18, 34, 56, 789)
    @test norm2.timeTZ  == ZonedDateTime(2016, 10, 3, 14, 34, 56, 789, TimeZone("America/New_York"))
    @test norm2.timeMS  == 1475519696789

    # 10. Converters
    @test convert(DateTime, norm1) == DateTime(2016, 10, 10, 16, 34, 56, 789)
    @test convert(ZonedDateTime, norm1) == ZonedDateTime(2016, 10, 10, 12, 34, 56, 789, TimeZone("America/New_York"))
    @test convert(Int64, norm1) == 1476117296789

    # 11. ZonedDateTime -> DateTime DST inner
    @test convert(DateTime, ZonedDateTime(2020, 3, 8, 7, tz"America/New_York")) == DateTime(2020, 3, 8, 7)
end

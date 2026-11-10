using Documenter, TimeUtilities

makedocs(
    sitename="TimeUtilities.jl Documentation",
    format=Documenter.HTML(
        prettyurls = false,
        edit_link="main",
    ),
    modules=[TimeUtilities],
)

deploydocs(
    repo = "github.com/bluesmoon/TimeUtilities.jl.git",
)

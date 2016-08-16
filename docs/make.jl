using Documenter, Hafta

makedocs(
    modules = [Hafta],
    format  = Documenter.Formats.HTML,
    sitename = "Hafta.jl",
    pages = [
        "Introduction" => "index.md",
        "api.md",
    ]
)

deploydocs(
    repo = "github.com/mortenpi/Hafta.jl.git",
    target = "build",
    julia = "0.5",
    make = nothing,
    deps = nothing,
)

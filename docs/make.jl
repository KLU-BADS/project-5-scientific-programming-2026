using Documenter
using DocumenterPlantUML
using Project5

# Doctests run in a bare module, so the package has to be brought into scope
# for them. Without this, every jldoctest fails with UndefVarError.
DocMeta.setdocmeta!(Project5, :DocTestSetup, :(using Project5); recursive = true)

makedocs(
    sitename = "Project5.jl",
    modules  = [Project5],
    # Write design.html rather than design/index.html, so that the built pages
    # can be opened from the file system. With the pretty form the links
    # between pages point at directories, which a browser cannot follow over
    # file://, and reading the documentation locally would need a web server.
    format   = Documenter.HTML(prettyurls = false),
    pages = [
        "Home"           => "index.md",
        "Project design" => "design.md",
        "Reference manual"  => "manual.md",
    ],
    # Fail the build if an exported function has no docstring.
    checkdocs = :exports,
)

# Deployment is handled by the GitHub Actions workflow in .github/workflows/docs.yml,
# which uploads docs/build directly to GitHub Pages.

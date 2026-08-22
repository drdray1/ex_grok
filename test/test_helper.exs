# `elixirc_paths(:test)` already compiles test/support, so this looks redundant —
# it is not. Without it, `mix test --cover` dies with a CaseClauseError inside
# :cover.get_abstract_code/2 while cover-compiling ExGrok.Fixtures, because
# `test_coverage: [ignore_modules: ...]` is applied only after cover_compile.
# Re-requiring the file replaces that beam with an in-memory module that cover
# skips. Costs a module-redefinition warning in the test env; buys the coverage
# gate that CI depends on.
Code.require_file("support/fixtures.ex", __DIR__)
# Live tests hit the real xAI API and need XAI_API_KEY. Excluded by default;
# run them with `mix test --only live` before cutting a release. Nothing else in
# this suite can catch "the API's shape is not what we think it is" — which is
# exactly how the response_format bug reached production.
ExUnit.start(exclude: [:live])

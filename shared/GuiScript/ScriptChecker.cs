namespace GuiScript;

public sealed record CheckResult(ScriptAst Ast, IReadOnlyList<Diagnostic> Diagnostics)
{
    public bool IsValid => Diagnostics.All(d => d.Severity != DiagnosticSeverity.Error);
}

/// <summary>
/// Entry point. The builder calls this while the user types; the player calls it again when
/// loading a package and refuses to run any script that is not valid.
/// </summary>
public static class ScriptChecker
{
    public static CheckResult Check(string source, ValidationContext context)
    {
        var diagnostics = new DiagnosticBag();

        int lines = source.Count(c => c == '\n') + 1;
        if (lines > context.Limits.MaxLines)
        {
            diagnostics.Error(Codes.TooManyLines, new SourceSpan(1, 1, 0),
                $"Script has {lines} lines; the limit is {context.Limits.MaxLines}");
            return new CheckResult(new ScriptAst(Array.Empty<Stmt>()), diagnostics.ToSortedList());
        }

        var tokens = new Lexer(source, diagnostics).Tokenize();
        var ast = new Parser(tokens, diagnostics).ParseScript();
        new Validator(context, diagnostics).Validate(ast);
        return new CheckResult(ast, diagnostics.ToSortedList());
    }
}

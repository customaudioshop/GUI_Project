namespace GuiScript;

public readonly record struct SourceSpan(int Line, int Column, int Length)
{
    /// <summary>Span from the start of this span to the end of <paramref name="end"/> (same line only).</summary>
    public SourceSpan To(SourceSpan end) =>
        end.Line == Line ? new SourceSpan(Line, Column, end.Column + end.Length - Column) : this;

    public override string ToString() => $"{Line}:{Column}";
}

public enum DiagnosticSeverity { Error, Warning }

public sealed record Diagnostic(DiagnosticSeverity Severity, string Code, string Message, SourceSpan Span)
{
    public override string ToString() =>
        $"{Span} {Severity.ToString().ToLowerInvariant()} {Code}: {Message}";
}

public sealed class DiagnosticBag
{
    private readonly List<Diagnostic> _items = new();

    public void Error(string code, SourceSpan span, string message) =>
        _items.Add(new Diagnostic(DiagnosticSeverity.Error, code, message, span));

    public void Warning(string code, SourceSpan span, string message) =>
        _items.Add(new Diagnostic(DiagnosticSeverity.Warning, code, message, span));

    public IReadOnlyList<Diagnostic> ToSortedList() =>
        _items.OrderBy(d => d.Span.Line).ThenBy(d => d.Span.Column).ToList();
}

/// <summary>Stable diagnostic codes. Messages may change or be localized; codes do not.</summary>
public static class Codes
{
    // Lexical
    public const string UnexpectedChar = "GS101";
    public const string UnterminatedString = "GS102";
    public const string InvalidEscape = "GS103";
    public const string InvalidNumber = "GS104";
    public const string BadVariableName = "GS105";

    // Syntax
    public const string UnexpectedToken = "GS201";
    public const string MissingEnd = "GS202";
    public const string StrayBlockKeyword = "GS203";
    public const string ExpectedExpression = "GS204";
    public const string ExpectedLineEnd = "GS205";
    public const string ExpectedVariable = "GS206";
    public const string ExpectedAssign = "GS207";
    public const string ExpectedRParen = "GS208";

    // Semantic
    public const string UnknownCommand = "GS301";
    public const string ArgumentCount = "GS302";
    public const string TypeMismatch = "GS303";
    public const string OutOfRange = "GS304";
    public const string UnknownDevice = "GS305";
    public const string DeviceProtocolMismatch = "GS306";
    public const string UndefinedVariable = "GS307";
    public const string UnknownFunction = "GS308";
    public const string ReadOnlyVariable = "GS309";
    public const string UnknownPage = "GS310";
    public const string InvalidHex = "GS311";
    public const string InvalidChoice = "GS312";
    public const string DivisionByZero = "GS313";
    public const string NotInteger = "GS314";
    public const string VariableTypeChanged = "GS315";
    public const string NotAValue = "GS316";

    // Safety limits
    public const string TooManyLines = "GS401";
    public const string NestingTooDeep = "GS402";
    public const string RepeatNotConstant = "GS403";
    public const string RepeatOutOfRange = "GS404";

    // Warnings
    public const string ConstantCondition = "GS501";
}

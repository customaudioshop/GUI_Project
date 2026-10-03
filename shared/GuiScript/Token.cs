namespace GuiScript;

public enum TokenKind
{
    Identifier, Variable, Number, String, Newline, Eof,
    Plus, Minus, Star, Slash, Percent,
    EqEq, NotEq, Less, LessEq, Greater, GreaterEq,
    Assign, LParen, RParen, Comma,
    // Keywords
    Set, If, Elif, Else, End, Repeat, And, Or, Not, True, False,
}

/// <summary>A piece of a string literal: plain text, or a <c>$name</c> to interpolate.</summary>
public sealed record StringPart(bool IsVariable, string Value, SourceSpan Span);

/// <summary>
/// For <see cref="TokenKind.Variable"/>, <see cref="Text"/> is the name without the leading '$'.
/// </summary>
public sealed record Token(TokenKind Kind, string Text, SourceSpan Span)
{
    public double NumberValue { get; init; }
    public IReadOnlyList<StringPart> Parts { get; init; } = Array.Empty<StringPart>();
}

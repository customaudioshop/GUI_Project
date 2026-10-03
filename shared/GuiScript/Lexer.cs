using System.Globalization;
using System.Text;

namespace GuiScript;

public sealed class Lexer
{
    private static readonly Dictionary<string, TokenKind> Keywords = new()
    {
        ["set"] = TokenKind.Set, ["if"] = TokenKind.If, ["elif"] = TokenKind.Elif,
        ["else"] = TokenKind.Else, ["end"] = TokenKind.End, ["repeat"] = TokenKind.Repeat,
        ["and"] = TokenKind.And, ["or"] = TokenKind.Or, ["not"] = TokenKind.Not,
        ["true"] = TokenKind.True, ["false"] = TokenKind.False,
    };

    private readonly record struct Mark(int Pos, int Line, int Col);

    private readonly string _src;
    private readonly DiagnosticBag _diagnostics;
    private int _pos;
    private int _line = 1;
    private int _col = 1;

    public Lexer(string source, DiagnosticBag diagnostics)
    {
        _src = source;
        _diagnostics = diagnostics;
    }

    public List<Token> Tokenize()
    {
        var tokens = new List<Token>();
        while (true)
        {
            SkipWhitespaceAndComments();
            if (AtEnd)
            {
                tokens.Add(new Token(TokenKind.Eof, "", new SourceSpan(_line, _col, 0)));
                return tokens;
            }

            char c = Peek();
            Token? token;
            if (c == '\n')
            {
                var start = Here();
                Advance();
                token = new Token(TokenKind.Newline, "\n", SpanFrom(start));
            }
            else if (c == '"') token = LexString();
            else if (char.IsAsciiDigit(c)) token = LexNumber();
            else if (IsIdentStart(c)) token = LexIdentifier();
            else if (c == '$') token = LexVariable();
            else token = LexOperator();

            if (token != null) tokens.Add(token);
        }
    }

    private bool AtEnd => _pos >= _src.Length;
    private char Peek(int offset = 0) => _pos + offset < _src.Length ? _src[_pos + offset] : '\0';
    private Mark Here() => new(_pos, _line, _col);
    private SourceSpan SpanFrom(Mark m) => new(m.Line, m.Col, Math.Max(1, _pos - m.Pos));

    private static bool IsIdentStart(char c) => char.IsAsciiLetter(c) || c == '_';
    private static bool IsIdentPart(char c) => char.IsAsciiLetterOrDigit(c) || c == '_';

    private char Advance()
    {
        char c = _src[_pos++];
        if (c == '\n') { _line++; _col = 1; }
        else _col++;
        return c;
    }

    private bool Match(char expected)
    {
        if (Peek() != expected) return false;
        Advance();
        return true;
    }

    private void SkipWhitespaceAndComments()
    {
        while (!AtEnd)
        {
            char c = Peek();
            if (c is ' ' or '\t' or '\r') Advance();
            else if (c == '#') { while (!AtEnd && Peek() != '\n') Advance(); }
            else break;
        }
    }

    private Token LexIdentifier()
    {
        var start = Here();
        // Dots are allowed between name parts so commands can be grouped: midi.note, dmx.fade
        while (IsIdentPart(Peek()) || (Peek() == '.' && IsIdentStart(Peek(1)))) Advance();
        string text = _src[start.Pos.._pos];
        var kind = Keywords.TryGetValue(text, out var keyword) ? keyword : TokenKind.Identifier;
        return new Token(kind, text, SpanFrom(start));
    }

    private Token? LexVariable()
    {
        var start = Here();
        Advance(); // $
        if (!IsIdentStart(Peek()))
        {
            _diagnostics.Error(Codes.BadVariableName, SpanFrom(start),
                "'$' must be followed by a variable name, e.g. $value");
            return null;
        }
        while (IsIdentPart(Peek())) Advance();
        return new Token(TokenKind.Variable, _src[(start.Pos + 1).._pos], SpanFrom(start));
    }

    private Token LexNumber()
    {
        var start = Here();
        double value;
        if (Peek() == '0' && Peek(1) is 'x' or 'X')
        {
            Advance();
            Advance();
            int digitsStart = _pos;
            while (char.IsAsciiHexDigit(Peek())) Advance();
            string hex = _src[digitsStart.._pos];
            value = hex.Length is > 0 and <= 8 ? Convert.ToInt64(hex, 16) : double.NaN;
        }
        else
        {
            while (char.IsAsciiDigit(Peek())) Advance();
            if (Peek() == '.' && char.IsAsciiDigit(Peek(1)))
            {
                Advance();
                while (char.IsAsciiDigit(Peek())) Advance();
            }
            value = double.Parse(_src[start.Pos.._pos], CultureInfo.InvariantCulture);
        }

        // "12abc" or "1.2.3" is one bad token, not a number followed by a name.
        if (IsIdentPart(Peek()) || Peek() == '.')
        {
            while (IsIdentPart(Peek()) || Peek() == '.') Advance();
            value = double.NaN;
        }

        string text = _src[start.Pos.._pos];
        var span = SpanFrom(start);
        if (double.IsNaN(value))
        {
            _diagnostics.Error(Codes.InvalidNumber, span, $"'{text}' is not a valid number");
            value = 0;
        }
        return new Token(TokenKind.Number, text, span) { NumberValue = value };
    }

    private Token LexString()
    {
        var start = Here();
        Advance(); // opening quote
        var parts = new List<StringPart>();
        var text = new StringBuilder();
        var textStart = Here();

        void FlushText()
        {
            if (text.Length > 0) parts.Add(new StringPart(false, text.ToString(), SpanFrom(textStart)));
            text.Clear();
        }

        while (!AtEnd && Peek() != '"' && Peek() != '\n')
        {
            char c = Peek();
            if (c == '\\')
            {
                var escStart = Here();
                Advance();
                if (AtEnd || Peek() == '\n') break;
                char e = Advance();
                switch (e)
                {
                    case 'n': text.Append('\n'); break;
                    case 't': text.Append('\t'); break;
                    case '"' or '\\' or '$': text.Append(e); break;
                    default:
                        _diagnostics.Error(Codes.InvalidEscape, SpanFrom(escStart),
                            $"Unknown escape '\\{e}'. Use \\n, \\t, \\\", \\\\ or \\$");
                        text.Append(e);
                        break;
                }
            }
            else if (c == '$')
            {
                var varStart = Here();
                Advance();
                if (!IsIdentStart(Peek()))
                {
                    _diagnostics.Error(Codes.BadVariableName, SpanFrom(varStart),
                        "'$' in text must be followed by a variable name. Write \\$ for a dollar sign");
                    continue;
                }
                while (IsIdentPart(Peek())) Advance();
                FlushText();
                parts.Add(new StringPart(true, _src[(varStart.Pos + 1).._pos], SpanFrom(varStart)));
                textStart = Here();
            }
            else
            {
                if (text.Length == 0) textStart = Here();
                text.Append(Advance());
            }
        }
        FlushText();

        if (Peek() == '"') Advance();
        else _diagnostics.Error(Codes.UnterminatedString, SpanFrom(start), "Text is missing its closing '\"'");

        return new Token(TokenKind.String, _src[start.Pos.._pos], SpanFrom(start)) { Parts = parts };
    }

    private Token? LexOperator()
    {
        var start = Here();
        char c = Advance();
        TokenKind? kind = c switch
        {
            '+' => TokenKind.Plus,
            '-' => TokenKind.Minus,
            '*' => TokenKind.Star,
            '/' => TokenKind.Slash,
            '%' => TokenKind.Percent,
            '(' => TokenKind.LParen,
            ')' => TokenKind.RParen,
            ',' => TokenKind.Comma,
            '=' => Match('=') ? TokenKind.EqEq : TokenKind.Assign,
            '!' => Match('=') ? TokenKind.NotEq : null,
            '<' => Match('=') ? TokenKind.LessEq : TokenKind.Less,
            '>' => Match('=') ? TokenKind.GreaterEq : TokenKind.Greater,
            _ => null,
        };

        if (kind == null)
        {
            string message = c == '!' ? "Use 'not' instead of '!'" : $"Unexpected character '{c}'";
            _diagnostics.Error(Codes.UnexpectedChar, SpanFrom(start), message);
            return null;
        }
        return new Token(kind.Value, _src[start.Pos.._pos], SpanFrom(start));
    }
}

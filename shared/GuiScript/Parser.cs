namespace GuiScript;

public sealed class Parser
{
    /// <summary>Thrown after a syntax error is reported, to abandon the current line.</summary>
    private sealed class ParseError : Exception { }

    private readonly List<Token> _tokens;
    private readonly DiagnosticBag _diagnostics;
    private int _i;

    public Parser(List<Token> tokens, DiagnosticBag diagnostics)
    {
        _tokens = tokens;
        _diagnostics = diagnostics;
    }

    public ScriptAst ParseScript()
    {
        var body = new List<Stmt>();
        while (true)
        {
            ParseStatementsInto(body);
            if (Check(TokenKind.Eof)) break;

            // elif/else/end with no open block
            var stray = Advance();
            _diagnostics.Error(Codes.StrayBlockKeyword, stray.Span,
                $"'{stray.Text}' has no matching 'if' or 'repeat'");
            SkipLine();
        }
        return new ScriptAst(body);
    }

    private Token Current => _tokens[_i];
    private Token Next => _tokens[Math.Min(_i + 1, _tokens.Count - 1)];
    private bool Check(TokenKind kind) => Current.Kind == kind;
    private bool AtLineEnd => Current.Kind is TokenKind.Newline or TokenKind.Eof;

    private Token Advance()
    {
        var token = Current;
        if (token.Kind != TokenKind.Eof) _i++;
        return token;
    }

    private void SkipLine()
    {
        while (!AtLineEnd) Advance();
    }

    private ParseError Error(string code, SourceSpan span, string message)
    {
        _diagnostics.Error(code, span, message);
        return new ParseError();
    }

    /// <summary>Parses statements until end of script or a block keyword (elif / else / end).</summary>
    private void ParseStatementsInto(List<Stmt> list)
    {
        while (true)
        {
            while (Check(TokenKind.Newline)) Advance();
            if (Current.Kind is TokenKind.Eof or TokenKind.Elif or TokenKind.Else or TokenKind.End) return;

            try { list.Add(ParseStatement()); }
            catch (ParseError) { SkipLine(); }
        }
    }

    private List<Stmt> ParseBlock()
    {
        var list = new List<Stmt>();
        ParseStatementsInto(list);
        return list;
    }

    private Stmt ParseStatement() => Current.Kind switch
    {
        TokenKind.Set => ParseSet(),
        TokenKind.If => ParseIf(),
        TokenKind.Repeat => ParseRepeat(),
        TokenKind.Identifier => ParseCommand(),
        TokenKind.Variable => throw Error(Codes.UnexpectedToken, Current.Span,
            $"To change a variable write: set ${Current.Text} = ..."),
        _ => throw Error(Codes.UnexpectedToken, Current.Span, $"Expected a command, got {Describe(Current)}"),
    };

    private Stmt ParseSet()
    {
        var keyword = Advance();
        if (!Check(TokenKind.Variable))
            throw Error(Codes.ExpectedVariable, Current.Span, "Expected a variable after 'set', e.g. set $level = 10");
        var variable = Advance();
        if (!Check(TokenKind.Assign))
            throw Error(Codes.ExpectedAssign, Current.Span, $"Expected '=' after ${variable.Text}");
        Advance();
        var value = ParseExpression();
        ExpectLineEnd();
        return new SetStmt(variable.Text, value, keyword.Span.To(value.Span));
    }

    private Stmt ParseIf()
    {
        var keyword = Advance();
        var branches = new List<IfBranch>();
        var condition = ParseHeaderExpression();
        branches.Add(new IfBranch(condition, ParseBlock()));

        while (Check(TokenKind.Elif))
        {
            Advance();
            var elifCondition = ParseHeaderExpression();
            branches.Add(new IfBranch(elifCondition, ParseBlock()));
        }

        List<Stmt>? elseBody = null;
        if (Check(TokenKind.Else))
        {
            Advance();
            ExpectLineEndOrSkip();
            elseBody = ParseBlock();
        }

        CloseBlock(keyword);
        return new IfStmt(branches, elseBody, keyword.Span);
    }

    private Stmt ParseRepeat()
    {
        var keyword = Advance();
        var count = ParseHeaderExpression();
        var body = ParseBlock();
        CloseBlock(keyword);
        return new RepeatStmt(count, body, keyword.Span);
    }

    private Stmt ParseCommand()
    {
        var name = Advance();
        var args = new List<Expr>();
        while (!AtLineEnd) args.Add(ParseArgument());
        return new CommandStmt(name.Text, args, name.Span);
    }

    /// <summary>
    /// Command arguments are single values separated by spaces, so calculations must be
    /// parenthesized: <c>dmx light1 1 ($value * 2)</c>. A leading '-' on a number is allowed.
    /// </summary>
    private Expr ParseArgument()
    {
        if (Check(TokenKind.Minus) && Next.Kind == TokenKind.Number)
        {
            var minus = Advance();
            var number = Advance();
            return new NumberExpr(-number.NumberValue, minus.Span.To(number.Span));
        }
        if (IsBinaryOperator(Current.Kind))
            throw Error(Codes.UnexpectedToken, Current.Span,
                $"Unexpected '{Current.Text}'. Put calculations in parentheses, e.g. dmx light1 1 ($value * 2)");
        return ParsePrimary();
    }

    /// <summary>The condition after if/elif or the count after repeat; recovers locally so the block still parses.</summary>
    private Expr ParseHeaderExpression()
    {
        try
        {
            var expr = ParseExpression();
            ExpectLineEnd();
            return expr;
        }
        catch (ParseError)
        {
            var span = Current.Span;
            SkipLine();
            return new ErrorExpr(span);
        }
    }

    private void CloseBlock(Token opener)
    {
        if (Check(TokenKind.End))
        {
            Advance();
            ExpectLineEndOrSkip();
            return;
        }
        _diagnostics.Error(Codes.MissingEnd, opener.Span,
            $"'{opener.Text}' on line {opener.Span.Line} is missing its 'end'");
    }

    private void ExpectLineEnd()
    {
        if (!AtLineEnd)
            throw Error(Codes.ExpectedLineEnd, Current.Span, $"Unexpected {Describe(Current)}; expected end of line");
    }

    private void ExpectLineEndOrSkip()
    {
        try { ExpectLineEnd(); }
        catch (ParseError) { SkipLine(); }
    }

    // Precedence, lowest first: or, and, not, comparison, + -, * / %, unary -, primary

    private Expr ParseExpression() => ParseOr();

    private Expr ParseOr()
    {
        var left = ParseAnd();
        while (Check(TokenKind.Or))
        {
            var op = Advance();
            var right = ParseAnd();
            left = new BinaryExpr(op.Kind, left, right, left.Span.To(right.Span));
        }
        return left;
    }

    private Expr ParseAnd()
    {
        var left = ParseNot();
        while (Check(TokenKind.And))
        {
            var op = Advance();
            var right = ParseNot();
            left = new BinaryExpr(op.Kind, left, right, left.Span.To(right.Span));
        }
        return left;
    }

    private Expr ParseNot()
    {
        if (!Check(TokenKind.Not)) return ParseComparison();
        var op = Advance();
        var operand = ParseNot();
        return new UnaryExpr(op.Kind, operand, op.Span.To(operand.Span));
    }

    private Expr ParseComparison()
    {
        var left = ParseAdditive();
        if (Current.Kind is TokenKind.EqEq or TokenKind.NotEq or TokenKind.Less or TokenKind.LessEq
            or TokenKind.Greater or TokenKind.GreaterEq)
        {
            var op = Advance();
            var right = ParseAdditive();
            left = new BinaryExpr(op.Kind, left, right, left.Span.To(right.Span));
        }
        return left;
    }

    private Expr ParseAdditive()
    {
        var left = ParseMultiplicative();
        while (Current.Kind is TokenKind.Plus or TokenKind.Minus)
        {
            var op = Advance();
            var right = ParseMultiplicative();
            left = new BinaryExpr(op.Kind, left, right, left.Span.To(right.Span));
        }
        return left;
    }

    private Expr ParseMultiplicative()
    {
        var left = ParseUnary();
        while (Current.Kind is TokenKind.Star or TokenKind.Slash or TokenKind.Percent)
        {
            var op = Advance();
            var right = ParseUnary();
            left = new BinaryExpr(op.Kind, left, right, left.Span.To(right.Span));
        }
        return left;
    }

    private Expr ParseUnary()
    {
        if (!Check(TokenKind.Minus)) return ParsePrimary();
        var op = Advance();
        var operand = ParseUnary();
        return new UnaryExpr(op.Kind, operand, op.Span.To(operand.Span));
    }

    private Expr ParsePrimary()
    {
        var token = Current;
        switch (token.Kind)
        {
            case TokenKind.Number:
                Advance();
                return new NumberExpr(token.NumberValue, token.Span);
            case TokenKind.String:
                Advance();
                return new StringExpr(token.Parts, token.Span);
            case TokenKind.True or TokenKind.False:
                Advance();
                return new BoolExpr(token.Kind == TokenKind.True, token.Span);
            case TokenKind.Variable:
                Advance();
                return new VariableExpr(token.Text, token.Span);
            case TokenKind.Identifier:
                Advance();
                // "clamp(" is a call; "light1 (" is a name followed by a parenthesized argument.
                if (Check(TokenKind.LParen) && IsAdjacent(token, Current)) return ParseCall(token);
                return new NameExpr(token.Text, token.Span);
            case TokenKind.LParen:
                Advance();
                var inner = ParseExpression();
                if (!Check(TokenKind.RParen)) throw Error(Codes.ExpectedRParen, Current.Span, "Expected ')'");
                Advance();
                return inner;
            default:
                throw Error(Codes.ExpectedExpression, token.Span, $"Expected a value, got {Describe(token)}");
        }
    }

    private Expr ParseCall(Token name)
    {
        Advance(); // (
        var args = new List<Expr>();
        if (!Check(TokenKind.RParen))
        {
            while (true)
            {
                args.Add(ParseExpression());
                if (!Check(TokenKind.Comma)) break;
                Advance();
            }
        }
        if (!Check(TokenKind.RParen)) throw Error(Codes.ExpectedRParen, Current.Span, $"Expected ')' to close {name.Text}(");
        var close = Advance();
        return new CallExpr(name.Text, args, name.Span.To(close.Span));
    }

    private static bool IsAdjacent(Token a, Token b) =>
        a.Span.Line == b.Span.Line && a.Span.Column + a.Span.Length == b.Span.Column;

    private static bool IsBinaryOperator(TokenKind kind) => kind is TokenKind.Plus or TokenKind.Minus
        or TokenKind.Star or TokenKind.Slash or TokenKind.Percent or TokenKind.EqEq or TokenKind.NotEq
        or TokenKind.Less or TokenKind.LessEq or TokenKind.Greater or TokenKind.GreaterEq
        or TokenKind.And or TokenKind.Or or TokenKind.Assign;

    private static string Describe(Token token) => token.Kind switch
    {
        TokenKind.Newline => "end of line",
        TokenKind.Eof => "end of script",
        TokenKind.Variable => $"'${token.Text}'",
        _ => $"'{token.Text}'",
    };
}

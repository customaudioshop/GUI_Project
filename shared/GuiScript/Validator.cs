using System.Globalization;

namespace GuiScript;

public sealed class ScriptLimits
{
    public int MaxLines { get; init; } = 500;
    public int MaxNesting { get; init; } = 8;
    public int MaxRepeat { get; init; } = 1000;
}

/// <summary>What a script is checked against: the package's devices and pages, and the commands the player supports.</summary>
public sealed class ValidationContext
{
    public CommandRegistry Commands { get; init; } = BuiltIns.CreateCommands();
    public FunctionRegistry Functions { get; init; } = BuiltIns.CreateFunctions();
    public ScriptLimits Limits { get; init; } = new();

    /// <summary>Device name to protocol id (see <see cref="Protocols"/>).</summary>
    public Dictionary<string, string> Devices { get; init; } = new();

    public HashSet<string> Pages { get; init; } = new();

    /// <summary>Read-only variables the player provides, without '$' (e.g. "value" for a fader's position).</summary>
    public Dictionary<string, ScriptType> ContextVariables { get; init; } = new();
}

/// <summary>
/// Semantic checks: commands, argument types and ranges, devices, variables and safety limits.
/// Values known only at run time (such as <c>$value</c>) cannot be range-checked here; the interpreter must check them.
/// </summary>
public sealed class Validator
{
    private readonly ValidationContext _ctx;
    private readonly DiagnosticBag _diagnostics;
    private readonly Dictionary<string, ScriptType> _vars;

    public Validator(ValidationContext context, DiagnosticBag diagnostics)
    {
        _ctx = context;
        _diagnostics = diagnostics;
        _vars = new Dictionary<string, ScriptType>(context.ContextVariables);
    }

    public void Validate(ScriptAst ast) => CheckBlock(ast.Body, 0);

    private void CheckBlock(IReadOnlyList<Stmt> body, int depth)
    {
        foreach (var stmt in body) CheckStatement(stmt, depth);
    }

    private void CheckStatement(Stmt stmt, int depth)
    {
        switch (stmt)
        {
            case CommandStmt command:
                CheckCommand(command);
                break;
            case SetStmt set:
                CheckSet(set);
                break;
            case IfStmt ifStmt:
                CheckNesting(ifStmt.Span, depth);
                foreach (var branch in ifStmt.Branches)
                {
                    CheckCondition(branch.Condition);
                    CheckBlock(branch.Body, depth + 1);
                }
                if (ifStmt.ElseBody != null) CheckBlock(ifStmt.ElseBody, depth + 1);
                break;
            case RepeatStmt repeat:
                CheckNesting(repeat.Span, depth);
                CheckRepeatCount(repeat.Count);
                CheckBlock(repeat.Body, depth + 1);
                break;
        }
    }

    private void CheckNesting(SourceSpan span, int depth)
    {
        if (depth + 1 > _ctx.Limits.MaxNesting)
            _diagnostics.Error(Codes.NestingTooDeep, span,
                $"Blocks are nested too deeply (limit {_ctx.Limits.MaxNesting})");
    }

    private void CheckCondition(Expr condition)
    {
        if (condition is ErrorExpr) return;
        var type = Infer(condition);
        if (type is not (ScriptType.Bool or ScriptType.Any))
            _diagnostics.Error(Codes.TypeMismatch, condition.Span,
                $"A condition must be true or false, got {TypeName(type)}. Compare it, e.g. $value > 0");
        else if (TryConstant(condition, out _))
            _diagnostics.Warning(Codes.ConstantCondition, condition.Span, "This condition never changes");
    }

    private void CheckRepeatCount(Expr count)
    {
        if (count is ErrorExpr) return;
        Infer(count);
        // A fixed count guarantees every script finishes.
        if (!TryConstant(count, out var value) || value is not double n)
        {
            _diagnostics.Error(Codes.RepeatNotConstant, count.Span,
                "The repeat count must be a fixed number such as 4");
            return;
        }
        if (n != Math.Floor(n) || n < 1 || n > _ctx.Limits.MaxRepeat)
            _diagnostics.Error(Codes.RepeatOutOfRange, count.Span,
                $"The repeat count must be a whole number from 1 to {_ctx.Limits.MaxRepeat}, got {Format(n)}");
    }

    private void CheckSet(SetStmt set)
    {
        var type = Infer(set.Value);
        if (_ctx.ContextVariables.ContainsKey(set.Variable))
        {
            _diagnostics.Error(Codes.ReadOnlyVariable, set.Span, $"${set.Variable} is provided by the player and can't be changed");
            return;
        }
        if (_vars.TryGetValue(set.Variable, out var previous)
            && previous != ScriptType.Any && type != ScriptType.Any && previous != type)
        {
            _diagnostics.Error(Codes.VariableTypeChanged, set.Span,
                $"${set.Variable} holds {TypeName(previous)}; it can't be set to {TypeName(type)}");
            return;
        }
        _vars[set.Variable] = type;
    }

    private void CheckCommand(CommandStmt command)
    {
        if (!_ctx.Commands.TryGet(command.Name, out var spec))
        {
            _diagnostics.Error(Codes.UnknownCommand, command.Span,
                $"Unknown command '{command.Name}'{Suggest(command.Name, _ctx.Commands.All.Select(c => c.Name))}");
            foreach (var arg in command.Args) InferUnlessName(arg);
            return;
        }

        if (command.Args.Count != spec.Params.Count)
            _diagnostics.Error(Codes.ArgumentCount, command.Span,
                $"'{spec.Name}' takes {spec.Params.Count} argument(s) but got {command.Args.Count}. Usage: {spec.Usage}");

        for (int i = 0; i < command.Args.Count; i++)
        {
            if (i < spec.Params.Count) CheckArgument(spec, spec.Params[i], command.Args[i]);
            else InferUnlessName(command.Args[i]);
        }
    }

    private void CheckArgument(CommandSpec command, ParamSpec param, Expr arg)
    {
        switch (param.Kind)
        {
            case ParamKind.Device:
                CheckDevice(command, param, arg);
                return;

            case ParamKind.Choice when arg is NameExpr name:
                CheckChoice(param, name.Name, name.Span);
                return;

            case ParamKind.Page when arg is NameExpr name:
                _diagnostics.Error(Codes.TypeMismatch, arg.Span, $"Page names are text: write \"{name.Name}\"");
                return;

            case var _ when arg is NameExpr name:
                _diagnostics.Error(Codes.NotAValue, arg.Span,
                    $"'{name.Name}' is not a value here. Did you mean ${name.Name} or \"{name.Name}\"?");
                return;
        }

        var type = Infer(arg);
        if (!Accepts(param.Kind, type))
        {
            _diagnostics.Error(Codes.TypeMismatch, arg.Span,
                $"<{param.Name}> of '{command.Name}' needs {KindName(param.Kind)}, got {TypeName(type)}");
            return;
        }
        if (TryConstant(arg, out var value)) CheckConstant(param, arg.Span, value);
    }

    private void CheckConstant(ParamSpec param, SourceSpan span, object value)
    {
        switch (param.Kind)
        {
            case ParamKind.Number when value is double n:
                if (param.IntegerOnly && n != Math.Floor(n))
                    _diagnostics.Error(Codes.NotInteger, span, $"<{param.Name}> must be a whole number, got {Format(n)}");
                else if (n < param.Min || n > param.Max)
                    _diagnostics.Error(Codes.OutOfRange, span, $"<{param.Name}> must be {RangeText(param)}, got {Format(n)}");
                break;
            case ParamKind.Hex when value is string s && !HexBytes.TryParse(s, out _):
                _diagnostics.Error(Codes.InvalidHex, span,
                    $"\"{s}\" is not valid hex. Write bytes as pairs of 0-9/A-F, e.g. \"01 A0 FF\"");
                break;
            case ParamKind.Choice when value is string s:
                CheckChoice(param, s, span);
                break;
            case ParamKind.Page when value is string s && !_ctx.Pages.Contains(s):
                _diagnostics.Error(Codes.UnknownPage, span, $"There is no page \"{s}\"{Suggest(s, _ctx.Pages)}");
                break;
        }
    }

    private void CheckChoice(ParamSpec param, string value, SourceSpan span)
    {
        if (!param.Options.Contains(value))
            _diagnostics.Error(Codes.InvalidChoice, span,
                $"'{value}' is not valid for <{param.Name}>. Use one of: {string.Join(", ", param.Options)}");
    }

    private void CheckDevice(CommandSpec command, ParamSpec param, Expr arg)
    {
        if (arg is not NameExpr name)
        {
            _diagnostics.Error(Codes.TypeMismatch, arg.Span, $"<{param.Name}> must be a device name such as mixer1");
            Infer(arg);
            return;
        }
        if (!_ctx.Devices.TryGetValue(name.Name, out var protocol))
        {
            _diagnostics.Error(Codes.UnknownDevice, arg.Span,
                $"Unknown device '{name.Name}'{Suggest(name.Name, _ctx.Devices.Keys)}");
            return;
        }
        if (param.Options.Count > 0 && !param.Options.Contains(protocol))
            _diagnostics.Error(Codes.DeviceProtocolMismatch, arg.Span,
                $"'{command.Name}' can't use '{name.Name}' ({protocol}); it needs a {string.Join(" / ", param.Options)} device");
    }

    private void InferUnlessName(Expr expr)
    {
        if (expr is not NameExpr) Infer(expr);
    }

    private ScriptType Infer(Expr expr)
    {
        switch (expr)
        {
            case NumberExpr:
                return ScriptType.Number;
            case BoolExpr:
                return ScriptType.Bool;
            case ErrorExpr:
                return ScriptType.Any;
            case StringExpr s:
                foreach (var part in s.Parts.Where(p => p.IsVariable)) LookupVariable(part.Value, part.Span);
                return ScriptType.String;
            case VariableExpr v:
                return LookupVariable(v.Name, v.Span);
            case NameExpr n:
                _diagnostics.Error(Codes.NotAValue, n.Span,
                    $"'{n.Name}' is not a value. Did you mean ${n.Name} or \"{n.Name}\"?");
                return ScriptType.Any;
            case UnaryExpr u:
                var operand = Infer(u.Operand);
                var want = u.Op == TokenKind.Not ? ScriptType.Bool : ScriptType.Number;
                RequireOperand(operand, want, u.Operand, u.Op);
                return want;
            case BinaryExpr b:
                return InferBinary(b);
            case CallExpr c:
                return InferCall(c);
            default:
                return ScriptType.Any;
        }
    }

    private ScriptType InferBinary(BinaryExpr b)
    {
        var left = Infer(b.Left);
        var right = Infer(b.Right);
        switch (b.Op)
        {
            case TokenKind.Plus:
                if (left == ScriptType.String || right == ScriptType.String) return ScriptType.String;
                RequireOperand(left, ScriptType.Number, b.Left, b.Op);
                RequireOperand(right, ScriptType.Number, b.Right, b.Op);
                return left == ScriptType.Any || right == ScriptType.Any ? ScriptType.Any : ScriptType.Number;

            case TokenKind.Minus or TokenKind.Star or TokenKind.Slash or TokenKind.Percent:
                RequireOperand(left, ScriptType.Number, b.Left, b.Op);
                RequireOperand(right, ScriptType.Number, b.Right, b.Op);
                if (b.Op is TokenKind.Slash or TokenKind.Percent && TryConstant(b.Right, out var divisor) && divisor is 0.0)
                    _diagnostics.Error(Codes.DivisionByZero, b.Right.Span, "Division by zero");
                return ScriptType.Number;

            case TokenKind.Less or TokenKind.LessEq or TokenKind.Greater or TokenKind.GreaterEq:
                RequireOperand(left, ScriptType.Number, b.Left, b.Op);
                RequireOperand(right, ScriptType.Number, b.Right, b.Op);
                return ScriptType.Bool;

            case TokenKind.EqEq or TokenKind.NotEq:
                if (left != ScriptType.Any && right != ScriptType.Any && left != right)
                    _diagnostics.Error(Codes.TypeMismatch, b.Span, $"Can't compare {TypeName(left)} with {TypeName(right)}");
                return ScriptType.Bool;

            default: // and, or
                RequireOperand(left, ScriptType.Bool, b.Left, b.Op);
                RequireOperand(right, ScriptType.Bool, b.Right, b.Op);
                return ScriptType.Bool;
        }
    }

    private ScriptType InferCall(CallExpr call)
    {
        var argTypes = call.Args.Select(Infer).ToList();
        if (!_ctx.Functions.TryGet(call.Name, out var spec))
        {
            _diagnostics.Error(Codes.UnknownFunction, call.Span,
                $"Unknown function '{call.Name}'{Suggest(call.Name, _ctx.Functions.All.Select(f => f.Name))}");
            return ScriptType.Any;
        }
        if (argTypes.Count != spec.Params.Count)
        {
            _diagnostics.Error(Codes.ArgumentCount, call.Span,
                $"{spec.Name}() takes {spec.Params.Count} argument(s) but got {argTypes.Count}");
            return spec.Returns;
        }
        for (int i = 0; i < argTypes.Count; i++)
        {
            var want = spec.Params[i];
            if (want != ScriptType.Any && argTypes[i] != ScriptType.Any && argTypes[i] != want)
                _diagnostics.Error(Codes.TypeMismatch, call.Args[i].Span,
                    $"Argument {i + 1} of {spec.Name}() must be {TypeName(want)}, got {TypeName(argTypes[i])}");
        }
        return spec.Returns;
    }

    private ScriptType LookupVariable(string name, SourceSpan span)
    {
        if (_vars.TryGetValue(name, out var type)) return type;
        _diagnostics.Error(Codes.UndefinedVariable, span,
            $"${name} is not defined{Suggest(name, _vars.Keys, prefix: "$")}. Set it first: set ${name} = ...");
        _vars[name] = ScriptType.Any; // report each missing variable once
        return ScriptType.Any;
    }

    private void RequireOperand(ScriptType actual, ScriptType wanted, Expr operand, TokenKind op)
    {
        if (actual != wanted && actual != ScriptType.Any)
            _diagnostics.Error(Codes.TypeMismatch, operand.Span,
                $"'{OperatorText(op)}' needs {TypeName(wanted)}, got {TypeName(actual)}");
    }

    private static bool Accepts(ParamKind kind, ScriptType type) => type == ScriptType.Any || kind switch
    {
        ParamKind.Number => type == ScriptType.Number,
        ParamKind.String => type is ScriptType.String or ScriptType.Number,
        ParamKind.Bool => type == ScriptType.Bool,
        ParamKind.Page or ParamKind.Hex or ParamKind.Choice => type == ScriptType.String,
        _ => true,
    };

    /// <summary>Folds literals and arithmetic on literals; anything involving variables or calls is not constant.</summary>
    public static bool TryConstant(Expr expr, out object value)
    {
        value = 0.0;
        switch (expr)
        {
            case NumberExpr n:
                value = n.Value;
                return true;
            case BoolExpr b:
                value = b.Value;
                return true;
            case StringExpr s when s.Parts.All(p => !p.IsVariable):
                value = string.Concat(s.Parts.Select(p => p.Value));
                return true;
            case UnaryExpr { Op: TokenKind.Minus } u when TryConstant(u.Operand, out var o) && o is double d:
                value = -d;
                return true;
            case UnaryExpr { Op: TokenKind.Not } u when TryConstant(u.Operand, out var o) && o is bool flag:
                value = !flag;
                return true;
            case BinaryExpr b when TryConstant(b.Left, out var l) && TryConstant(b.Right, out var r):
                return TryFold(b.Op, l, r, out value);
            default:
                return false;
        }
    }

    private static bool TryFold(TokenKind op, object left, object right, out object value)
    {
        value = 0.0;
        if (op == TokenKind.Plus && (left is string || right is string))
        {
            value = ToText(left) + ToText(right);
            return true;
        }
        if (left is double l && right is double r)
        {
            object? result = op switch
            {
                TokenKind.Plus => l + r,
                TokenKind.Minus => l - r,
                TokenKind.Star => l * r,
                TokenKind.Slash when r != 0 => l / r,
                TokenKind.Percent when r != 0 => l % r,
                TokenKind.Less => l < r,
                TokenKind.LessEq => l <= r,
                TokenKind.Greater => l > r,
                TokenKind.GreaterEq => l >= r,
                TokenKind.EqEq => l == r,
                TokenKind.NotEq => l != r,
                _ => null,
            };
            if (result == null) return false;
            value = result;
            return true;
        }
        if (left is bool lb && right is bool rb)
        {
            object? result = op switch
            {
                TokenKind.And => lb && rb,
                TokenKind.Or => lb || rb,
                TokenKind.EqEq => lb == rb,
                TokenKind.NotEq => lb != rb,
                _ => null,
            };
            if (result == null) return false;
            value = result;
            return true;
        }
        return false;
    }

    private static string ToText(object value) => value switch
    {
        double d => Format(d),
        bool b => b ? "true" : "false",
        _ => value.ToString() ?? "",
    };

    private static string Format(double n) => n.ToString(CultureInfo.InvariantCulture);

    private static string RangeText(ParamSpec p) => (p.Min, p.Max) switch
    {
        ({ } min, { } max) => $"from {Format(min)} to {Format(max)}",
        ({ } min, null) => $"at least {Format(min)}",
        (null, { } max) => $"at most {Format(max)}",
        _ => "any number",
    };

    private static string TypeName(ScriptType type) => type switch
    {
        ScriptType.Number => "a number",
        ScriptType.String => "text",
        ScriptType.Bool => "true/false",
        _ => "a value",
    };

    private static string KindName(ParamKind kind) => kind switch
    {
        ParamKind.Number => "a number",
        ParamKind.Bool => "true/false",
        ParamKind.String or ParamKind.Page or ParamKind.Hex or ParamKind.Choice => "text",
        _ => "a value",
    };

    private static string OperatorText(TokenKind op) => op switch
    {
        TokenKind.Plus => "+", TokenKind.Minus => "-", TokenKind.Star => "*", TokenKind.Slash => "/",
        TokenKind.Percent => "%", TokenKind.Less => "<", TokenKind.LessEq => "<=", TokenKind.Greater => ">",
        TokenKind.GreaterEq => ">=", TokenKind.And => "and", TokenKind.Or => "or", TokenKind.Not => "not",
        _ => op.ToString(),
    };

    private static string Suggest(string name, IEnumerable<string> candidates, string prefix = "")
    {
        string? best = null;
        int bestDistance = int.MaxValue;
        foreach (var candidate in candidates)
        {
            int distance = Levenshtein(name, candidate);
            if (distance < bestDistance)
            {
                best = candidate;
                bestDistance = distance;
            }
        }
        return best != null && bestDistance <= Math.Min(2, name.Length - 1)
            ? $". Did you mean '{prefix}{best}'?"
            : "";
    }

    private static int Levenshtein(string a, string b)
    {
        var row = Enumerable.Range(0, b.Length + 1).ToArray();
        for (int i = 1; i <= a.Length; i++)
        {
            int diagonal = row[0];
            row[0] = i;
            for (int j = 1; j <= b.Length; j++)
            {
                int above = row[j];
                int cost = char.ToLowerInvariant(a[i - 1]) == char.ToLowerInvariant(b[j - 1]) ? 0 : 1;
                row[j] = Math.Min(Math.Min(row[j] + 1, row[j - 1] + 1), diagonal + cost);
                diagonal = above;
            }
        }
        return row[b.Length];
    }
}

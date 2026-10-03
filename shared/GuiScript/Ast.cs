namespace GuiScript;

public sealed record ScriptAst(IReadOnlyList<Stmt> Body);

public abstract record Stmt(SourceSpan Span);

/// <summary><c>dmx light1 1 255</c></summary>
public sealed record CommandStmt(string Name, IReadOnlyList<Expr> Args, SourceSpan Span) : Stmt(Span);

/// <summary><c>set $level = $value * 2</c></summary>
public sealed record SetStmt(string Variable, Expr Value, SourceSpan Span) : Stmt(Span);

public sealed record IfBranch(Expr Condition, IReadOnlyList<Stmt> Body);

public sealed record IfStmt(IReadOnlyList<IfBranch> Branches, IReadOnlyList<Stmt>? ElseBody, SourceSpan Span) : Stmt(Span);

public sealed record RepeatStmt(Expr Count, IReadOnlyList<Stmt> Body, SourceSpan Span) : Stmt(Span);

public abstract record Expr(SourceSpan Span);

public sealed record NumberExpr(double Value, SourceSpan Span) : Expr(Span);

public sealed record StringExpr(IReadOnlyList<StringPart> Parts, SourceSpan Span) : Expr(Span);

public sealed record BoolExpr(bool Value, SourceSpan Span) : Expr(Span);

public sealed record VariableExpr(string Name, SourceSpan Span) : Expr(Span);

/// <summary>A bare identifier such as a device name (<c>mixer1</c>) or a choice (<c>on</c>).</summary>
public sealed record NameExpr(string Name, SourceSpan Span) : Expr(Span);

public sealed record UnaryExpr(TokenKind Op, Expr Operand, SourceSpan Span) : Expr(Span);

public sealed record BinaryExpr(TokenKind Op, Expr Left, Expr Right, SourceSpan Span) : Expr(Span);

public sealed record CallExpr(string Name, IReadOnlyList<Expr> Args, SourceSpan Span) : Expr(Span);

/// <summary>Placeholder for an expression that failed to parse; already reported.</summary>
public sealed record ErrorExpr(SourceSpan Span) : Expr(Span);

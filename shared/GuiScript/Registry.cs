using System.Diagnostics.CodeAnalysis;

namespace GuiScript;

public enum ScriptType { Number, String, Bool, Any }

public enum ParamKind
{
    Number,
    /// <summary>Text; numbers are accepted and converted.</summary>
    String,
    Bool,
    Any,
    /// <summary>A bare device name; <see cref="ParamSpec.Options"/> lists the allowed protocols.</summary>
    Device,
    /// <summary>A page name in quotes; checked against the package's pages.</summary>
    Page,
    /// <summary>One of <see cref="ParamSpec.Options"/>, written bare (<c>on</c>) or quoted.</summary>
    Choice,
    /// <summary>Hex bytes as text, e.g. "01 A0 FF".</summary>
    Hex,
}

public sealed class ParamSpec
{
    public required string Name { get; init; }
    public required ParamKind Kind { get; init; }
    public double? Min { get; init; }
    public double? Max { get; init; }
    public bool IntegerOnly { get; init; }
    public IReadOnlyList<string> Options { get; init; } = Array.Empty<string>();

    public static ParamSpec Int(string name, int min, int max) =>
        new() { Name = name, Kind = ParamKind.Number, Min = min, Max = max, IntegerOnly = true };

    public static ParamSpec Number(string name, double? min = null, double? max = null) =>
        new() { Name = name, Kind = ParamKind.Number, Min = min, Max = max };

    public static ParamSpec Text(string name) => new() { Name = name, Kind = ParamKind.String };
    public static ParamSpec Bool(string name) => new() { Name = name, Kind = ParamKind.Bool };
    public static ParamSpec AnyValue(string name) => new() { Name = name, Kind = ParamKind.Any };
    public static ParamSpec Page(string name) => new() { Name = name, Kind = ParamKind.Page };
    public static ParamSpec Hex(string name) => new() { Name = name, Kind = ParamKind.Hex };

    public static ParamSpec Device(string name, params string[] protocols) =>
        new() { Name = name, Kind = ParamKind.Device, Options = protocols };

    public static ParamSpec Choice(string name, params string[] values) =>
        new() { Name = name, Kind = ParamKind.Choice, Options = values };
}

public sealed class CommandSpec
{
    public required string Name { get; init; }
    public required string Description { get; init; }
    public required IReadOnlyList<ParamSpec> Params { get; init; }

    public string Usage => Params.Count == 0
        ? Name
        : $"{Name} {string.Join(" ", Params.Select(p => $"<{p.Name}>"))}";
}

public sealed class CommandRegistry
{
    private readonly Dictionary<string, CommandSpec> _commands = new(StringComparer.Ordinal);

    public IEnumerable<CommandSpec> All => _commands.Values;

    public void Register(string name, string description, params ParamSpec[] parameters) =>
        Register(new CommandSpec { Name = name, Description = description, Params = parameters });

    public void Register(CommandSpec spec)
    {
        if (!_commands.TryAdd(spec.Name, spec))
            throw new ArgumentException($"Command '{spec.Name}' is already registered");
    }

    public bool TryGet(string name, [MaybeNullWhen(false)] out CommandSpec spec) =>
        _commands.TryGetValue(name, out spec);
}

/// <summary>A pure function usable inside expressions, e.g. <c>clamp($value, 0, 255)</c>.</summary>
public sealed record FunctionSpec(string Name, IReadOnlyList<ScriptType> Params, ScriptType Returns, string Description);

public sealed class FunctionRegistry
{
    private readonly Dictionary<string, FunctionSpec> _functions = new(StringComparer.Ordinal);

    public IEnumerable<FunctionSpec> All => _functions.Values;

    public void Register(string name, ScriptType returns, string description, params ScriptType[] parameters) =>
        Register(new FunctionSpec(name, parameters, returns, description));

    public void Register(FunctionSpec spec)
    {
        if (!_functions.TryAdd(spec.Name, spec))
            throw new ArgumentException($"Function '{spec.Name}' is already registered");
    }

    public bool TryGet(string name, [MaybeNullWhen(false)] out FunctionSpec spec) =>
        _functions.TryGetValue(name, out spec);
}
